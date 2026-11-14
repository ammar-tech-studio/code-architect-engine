from __future__ import annotations

import os
import sys
from pathlib import Path

from src.llm.router import ModelRouter
from src.memory.skill_writer import slugify
from src.memory.store import BrainStore
from src.sandbox.verifier import verify_project_bundle

OUTPUT_BASE = Path("workspace_outputs")


def _safe_write(project_root: Path, rel_path: str, content: str) -> Path:
    """Prevent Path Traversal so issue text can never overwrite repo system files."""
    target = (project_root / rel_path).resolve()
    if not target.is_relative_to(project_root.resolve()):
        raise ValueError(f"Unsafe path outside project scope: {rel_path}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content.rstrip() + "\n", encoding="utf-8")
    return target


def main() -> int:
    issue_num = os.environ["ISSUE_NUMBER"]
    issue_title = os.environ["ISSUE_TITLE"]
    issue_body = os.environ.get("ISSUE_BODY", "")

    store = BrainStore("memory/brain.db")
    router = ModelRouter()

    try:
        relevant = store.search_relevant(f"{issue_title} {issue_body}", limit=4)
        memory_context = "\n\n".join(
            f"### Learned Pattern: {r['title']}\n{r['summary']}\nBest Practices: {r['best_practices_json']}"
            for r in relevant
        ) or "No prior matching skills yet."

        schema_prompt = (
            "You are a Principal AI Software Architect. Design and implement the user's requested feature/project "
            "using Python 3.11+ clean architecture. Return ONLY valid JSON:\n"
            '{"project_slug": str, "architecture_plan": str, '
            '"files": [{"path": "relative/path.py", "content": str}], '
            '"verification_script": str}'
        )
        plan, resp = router.complete_json(
            "reasoning",
            [
                {"role": "system", "content": schema_prompt},
                {
                    "role": "user",
                    "content": (
                        f"Issue #{issue_num}: {issue_title}\n\nDetails:\n{issue_body}\n\n"
                        f"Accumulated Brain Context:\n{memory_context}"
                    ),
                },
            ],
            max_tokens=4096,
        )

        project_slug = slugify(plan.get("project_slug") or issue_title)
        project_root = (OUTPUT_BASE / f"issue_{issue_num}_{project_slug}").resolve()
        project_root.mkdir(parents=True, exist_ok=True)

        for file_spec in plan["files"]:
            _safe_write(project_root, file_spec["path"], file_spec["content"])

        current_files: list[dict[str, str]] = list(plan["files"])
        test_code = plan["verification_script"]
        ver_result = verify_project_bundle(project_root, test_code, timeout_sec=30)
        attempts = 1
        while not ver_result.passed and attempts < 3:
            attempts += 1
            err_summary = f"[{ver_result.stage}] {ver_result.stderr}".strip()
            prior_fixes = store.search_error_fixes(err_summary, limit=2)
            fixes_hint = (
                "\n\nKnown fixes from memory:\n"
                + "\n".join(f"- {f['root_cause']}: {f['verified_fix'][:250]}" for f in prior_fixes)
                if prior_fixes
                else ""
            )
            files_snapshot = "\n\n".join(
                f"### File: `{f['path']}`\n```python\n{f['content']}\n```" for f in current_files
            )
            fix, _ = router.complete_json(
                "coding",
                [
                    {
                        "role": "system",
                        "content": (
                            "Fix the broken project files and/or verification script so the bundle passes sandbox checks. "
                            "Return ONLY valid JSON: "
                            '{"updated_files": [{"path": "relative/path.py", "content": str}], '
                            '"verification_script": str}'
                        ),
                    },
                    {
                        "role": "user",
                        "content": (
                            f"Project Files:\n{files_snapshot}\n\n"
                            f"Verification Script (`verify_smoke.py`):\n```python\n{test_code}\n```\n\n"
                            f"Sandbox Failure ({ver_result.stage}):\n{ver_result.stderr}{fixes_hint}"
                        ),
                    },
                ],
                max_tokens=4096,
            )
            for updated in fix.get("updated_files") or []:
                if "path" in updated and "content" in updated:
                    _safe_write(project_root, updated["path"], updated["content"])
                    for existing in current_files:
                        if existing["path"] == updated["path"]:
                            existing["content"] = updated["content"]
                            break
                    else:
                        current_files.append({"path": updated["path"], "content": updated["content"]})

            if fix.get("verification_script"):
                test_code = fix["verification_script"]
            elif fix.get("fixed_code"):
                test_code = fix["fixed_code"]

            ver_result = verify_project_bundle(project_root, test_code, timeout_sec=30)

        _safe_write(project_root, "verify_smoke.py", test_code)
        _safe_write(
            project_root,
            "ARCHITECTURE_PLAN.md",
            f"# Issue #{issue_num}: {issue_title}\n\n"
            f"- **Model:** `{resp.provider}/{resp.model}`\n"
            f"- **Sandbox Verification:** `{'PASSED' if ver_result.passed else 'NEEDS_REVIEW'}`\n\n"
            f"{plan['architecture_plan']}\n",
        )

        plan_comment = (
            f"### Architectural Plan for #{issue_num}\n\n"
            f"- **Model:** `{resp.provider}/{resp.model}`\n"
            f"- **Output Directory:** `{OUTPUT_BASE.name}/issue_{issue_num}_{project_slug}`\n"
            f"- **Bundle Sandbox Test:** `{'PASSED' if ver_result.passed else 'NEEDS_REVIEW'}`\n\n"
            f"{plan['architecture_plan']}\n"
        )
        Path("plan_comment.md").write_text(plan_comment, encoding="utf-8")

        pr_summary = (
            f"Automated implementation for #{issue_num} generated by `code-architect-engine`.\n\n"
            f"- **Output Directory:** `{OUTPUT_BASE.name}/issue_{issue_num}_{project_slug}`\n"
            f"- **Bundle Sandbox Test:** {'PASSED' if ver_result.passed else 'FAILED (needs manual review)'}\n"
            f"- **Model Used:** `{resp.provider}/{resp.model}`\n\n"
            f"Closes #{issue_num}\n"
        )
        Path("pr_body.txt").write_text(pr_summary, encoding="utf-8")
        Path("pr_branch.txt").write_text(f"agent/issue-{issue_num}", encoding="utf-8")
        return 0
    finally:
        # Read-only in issue_architect; skip VACUUM so brain.db does not cause binary PR merge conflicts
        store.close_for_git(compact=False)


if __name__ == "__main__":
    sys.exit(main())
