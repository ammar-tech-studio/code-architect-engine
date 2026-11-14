from __future__ import annotations

import json
import re
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class BrainStore:
    """Persistent SQLite + FTS5 memory store with clean Git-friendly shutdown."""

    def __init__(self, db_path: str | Path = "memory/brain.db") -> None:
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(str(self.db_path))
        self.conn.row_factory = sqlite3.Row
        self._init_schema()

    def _init_schema(self) -> None:
        self.conn.executescript(
            """
            PRAGMA foreign_keys = ON;

            CREATE TABLE IF NOT EXISTS knowledge (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                topic_slug TEXT UNIQUE NOT NULL,
                title TEXT NOT NULL,
                category TEXT NOT NULL,
                summary TEXT NOT NULL,
                best_practices_json TEXT NOT NULL,
                code_template TEXT NOT NULL,
                source_urls_json TEXT NOT NULL,
                verified INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
                topic_slug,
                title,
                category,
                summary,
                best_practices_json,
                content='knowledge',
                content_rowid='id'
            );

            CREATE TRIGGER IF NOT EXISTS knowledge_ai AFTER INSERT ON knowledge BEGIN
                INSERT INTO knowledge_fts(rowid, topic_slug, title, category, summary, best_practices_json)
                VALUES (new.id, new.topic_slug, new.title, new.category, new.summary, new.best_practices_json);
            END;

            CREATE TRIGGER IF NOT EXISTS knowledge_ad AFTER DELETE ON knowledge BEGIN
                INSERT INTO knowledge_fts(knowledge_fts, rowid, topic_slug, title, category, summary, best_practices_json)
                VALUES ('delete', old.id, old.topic_slug, old.title, old.category, old.summary, old.best_practices_json);
            END;

            CREATE TRIGGER IF NOT EXISTS knowledge_au AFTER UPDATE ON knowledge BEGIN
                INSERT INTO knowledge_fts(knowledge_fts, rowid, topic_slug, title, category, summary, best_practices_json)
                VALUES ('delete', old.id, old.topic_slug, old.title, old.category, old.summary, old.best_practices_json);
                INSERT INTO knowledge_fts(rowid, topic_slug, title, category, summary, best_practices_json)
                VALUES (new.id, new.topic_slug, new.title, new.category, new.summary, new.best_practices_json);
            END;

            CREATE TABLE IF NOT EXISTS error_patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                topic_slug TEXT NOT NULL,
                error_signature TEXT NOT NULL,
                root_cause TEXT NOT NULL,
                verified_fix TEXT NOT NULL,
                created_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS learning_runs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                topic_slug TEXT NOT NULL,
                status TEXT NOT NULL,
                attempts INTEGER NOT NULL,
                provider_used TEXT NOT NULL,
                duration_sec REAL NOT NULL,
                notes TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            """
        )
        self.conn.commit()

    def has_topic(self, topic_slug: str) -> bool:
        row = self.conn.execute(
            "SELECT 1 FROM knowledge WHERE topic_slug = ? LIMIT 1", (topic_slug,)
        ).fetchone()
        return row is not None

    def upsert_knowledge(
        self,
        *,
        topic_slug: str,
        title: str,
        category: str,
        summary: str,
        best_practices: list[str],
        code_template: str,
        source_urls: list[str],
    ) -> None:
        now = _utc_now()
        self.conn.execute(
            """
            INSERT INTO knowledge (
                topic_slug, title, category, summary,
                best_practices_json, code_template, source_urls_json,
                verified, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(topic_slug) DO UPDATE SET
                title = excluded.title,
                category = excluded.category,
                summary = excluded.summary,
                best_practices_json = excluded.best_practices_json,
                code_template = excluded.code_template,
                source_urls_json = excluded.source_urls_json,
                verified = 1,
                updated_at = excluded.updated_at
            """,
            (
                topic_slug,
                title,
                category,
                summary,
                json.dumps(best_practices, ensure_ascii=False),
                code_template,
                json.dumps(source_urls, ensure_ascii=False),
                now,
                now,
            ),
        )
        self.conn.commit()

    def record_error_fix(
        self, topic_slug: str, error_signature: str, root_cause: str, verified_fix: str
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO error_patterns (topic_slug, error_signature, root_cause, verified_fix, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (topic_slug, error_signature[:500], root_cause[:1000], verified_fix[:1500], _utc_now()),
        )
        self.conn.commit()

    def log_run(
        self,
        *,
        topic_slug: str,
        status: str,
        attempts: int,
        provider_used: str,
        duration_sec: float,
        notes: str = "",
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO learning_runs (topic_slug, status, attempts, provider_used, duration_sec, notes, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (topic_slug, status, attempts, provider_used, round(duration_sec, 2), notes[:1000], _utc_now()),
        )
        self.conn.commit()

    def search_relevant(self, query: str, limit: int = 5) -> list[dict[str, Any]]:
        tokens = [t for t in re.findall(r"[A-Za-z0-9_]{2,}", query)][:8]
        if not tokens:
            rows = self.conn.execute(
                "SELECT * FROM knowledge ORDER BY updated_at DESC LIMIT ?", (limit,)
            ).fetchall()
            return [dict(r) for r in rows]

        fts_query = " OR ".join(tokens)
        try:
            rows = self.conn.execute(
                """
                SELECT k.* FROM knowledge k
                JOIN knowledge_fts f ON k.id = f.rowid
                WHERE knowledge_fts MATCH ?
                ORDER BY bm25(knowledge_fts)
                LIMIT ?
                """,
                (fts_query, limit),
            ).fetchall()
        except sqlite3.OperationalError:
            like = f"%{tokens[0]}%"
            rows = self.conn.execute(
                "SELECT * FROM knowledge WHERE title LIKE ? OR summary LIKE ? LIMIT ?",
                (like, like, limit),
            ).fetchall()

        return [dict(r) for r in rows]

    def list_all_skills_meta(self) -> list[dict[str, str]]:
        rows = self.conn.execute(
            "SELECT topic_slug, title, category, updated_at FROM knowledge ORDER BY updated_at DESC"
        ).fetchall()
        return [dict(r) for r in rows]

    def search_error_fixes(self, error_text: str, limit: int = 3) -> list[dict[str, Any]]:
        """Retrieve previously verified fixes matching similar error signatures."""
        tokens = [
            t for t in re.findall(r"[A-Za-z_][A-Za-z0-9_]{3,}", error_text)
            if t.lower() not in {"traceback", "most", "recent", "call", "last", "file", "line", "module"}
        ][:6]
        if not tokens:
            return []

        clauses = " OR ".join("error_signature LIKE ?" for _ in tokens)
        params: list[Any] = [f"%{t}%" for t in tokens]
        params.append(limit)
        rows = self.conn.execute(
            f"""
            SELECT topic_slug, error_signature, root_cause, verified_fix
            FROM error_patterns
            WHERE {clauses}
            ORDER BY id DESC
            LIMIT ?
            """,
            params,
        ).fetchall()
        return [dict(r) for r in rows]

    def export_telemetry_summary(self) -> dict[str, Any]:
        """Export lightweight JSON telemetry for the Flutter dashboard."""
        skills_count = self.conn.execute("SELECT COUNT(*) FROM knowledge").fetchone()[0]
        errors_count = self.conn.execute("SELECT COUNT(*) FROM error_patterns").fetchone()[0]
        runs_rows = self.conn.execute(
            """
            SELECT provider_used, status, COUNT(*) as cnt, AVG(duration_sec) as avg_sec
            FROM learning_runs
            GROUP BY provider_used, status
            ORDER BY cnt DESC
            """
        ).fetchall()
        recent_runs = self.conn.execute(
            """
            SELECT topic_slug, status, attempts, provider_used, duration_sec, created_at
            FROM learning_runs
            ORDER BY id DESC
            LIMIT 10
            """
        ).fetchall()
        return {
            "updated_at": _utc_now(),
            "total_skills": skills_count,
            "total_error_fixes": errors_count,
            "provider_stats": [dict(r) for r in runs_rows],
            "recent_runs": [dict(r) for r in recent_runs],
        }

    def close_for_git(self, compact: bool = True) -> None:
        """Close SQLite cleanly; compact with DELETE journal + VACUUM when modified."""
        self.conn.commit()
        if compact:
            self.conn.execute("PRAGMA journal_mode = DELETE;")
            self.conn.execute("VACUUM;")
        self.conn.close()
