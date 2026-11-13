from __future__ import annotations

import ast
import os
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


@dataclass
class VerificationResult:
    passed: bool
    stage: str
    stdout: str
    stderr: str


def _build_clean_env() -> dict[str, str]:
    """Strip all API keys and tokens before running LLM-generated code."""
    allowed_keys = ("PATH", "PATHEXT", "SYSTEMROOT", "TEMP", "TMP", "HOME", "LANG")
    clean = {k: os.environ[k] for k in allowed_keys if k in os.environ}
    clean["PYTHONIOENCODING"] = "utf-8"
    clean["PYTHONDONTWRITEBYTECODE"] = "1"
    return clean


def _run_script_in_dir(script_path: Path, workdir: Path, timeout_sec: int) -> VerificationResult:
    clean_env = _build_clean_env()
    clean_env["PYTHONPATH"] = str(workdir)

    compile_proc = subprocess.run(
        [sys.executable, "-m", "py_compile", str(script_path)],
        cwd=str(workdir),
        env=clean_env,
        capture_output=True,
        text=True,
        timeout=10,
    )
    if compile_proc.returncode != 0:
        return VerificationResult(
            passed=False,
            stage="py_compile",
            stdout=compile_proc.stdout,
            stderr=compile_proc.stderr,
        )

    try:
        run_proc = subprocess.run(
            [sys.executable, str(script_path)],
            cwd=str(workdir),
            env=clean_env,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
        return VerificationResult(
            passed=(run_proc.returncode == 0),
            stage="runtime",
            stdout=run_proc.stdout[-2000:],
            stderr=run_proc.stderr[-2500:],
        )
    except subprocess.TimeoutExpired:
        return VerificationResult(
            passed=False,
            stage="runtime_timeout",
            stdout="",
            stderr=f"Execution exceeded strict {timeout_sec}s sandbox timeout.",
        )


def verify_python_code(code: str, timeout_sec: int = 25) -> VerificationResult:
    """Static AST check + isolated runtime execution in a clean temporary directory."""
    try:
        ast.parse(code)
    except SyntaxError as exc:
        return VerificationResult(
            passed=False,
            stage="ast_parse",
            stdout="",
            stderr=f"SyntaxError at line {exc.lineno}: {exc.msg}",
        )

    with tempfile.TemporaryDirectory(prefix="cae_sandbox_") as tmpdir:
        work = Path(tmpdir)
        script_path = work / "experiment.py"
        script_path.write_text(code, encoding="utf-8")
        return _run_script_in_dir(script_path, work, timeout_sec)


def verify_project_bundle(project_dir: Path, test_code: str, timeout_sec: int = 30) -> VerificationResult:
    """Validate all generated .py files in project_dir and run test_code against a temp copy."""
    for py_file in project_dir.rglob("*.py"):
        try:
            ast.parse(py_file.read_text(encoding="utf-8"))
        except SyntaxError as exc:
            rel = py_file.relative_to(project_dir)
            return VerificationResult(
                passed=False,
                stage="project_ast_parse",
                stdout="",
                stderr=f"SyntaxError in {rel} at line {exc.lineno}: {exc.msg}",
            )

    try:
        ast.parse(test_code)
    except SyntaxError as exc:
        return VerificationResult(
            passed=False,
            stage="test_ast_parse",
            stdout="",
            stderr=f"SyntaxError in verification script at line {exc.lineno}: {exc.msg}",
        )

    with tempfile.TemporaryDirectory(prefix="cae_bundle_") as tmpdir:
        sandbox_root = Path(tmpdir) / "project"
        shutil.copytree(project_dir, sandbox_root)
        script_path = sandbox_root / "verify_smoke.py"
        script_path.write_text(test_code, encoding="utf-8")
        return _run_script_in_dir(script_path, sandbox_root, timeout_sec)
