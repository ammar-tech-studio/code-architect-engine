from __future__ import annotations

import re
from pathlib import Path


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:64] or "unnamed-skill"


def write_antigravity_skill(
    *,
    skills_root: str | Path,
    slug: str,
    title: str,
    description: str,
    category: str,
    summary: str,
    best_practices: list[str],
    verified_code: str,
    source_urls: list[str],
    all_skills_meta: list[dict[str, str]],
) -> Path:
    """Write a skill package compatible with Google Antigravity Progressive Disclosure."""
    root = Path(skills_root)
    clean_slug = slugify(slug)
    skill_dir = root / clean_slug
    examples_dir = skill_dir / "examples"
    examples_dir.mkdir(parents=True, exist_ok=True)

    example_file = examples_dir / "verified_example.py"
    example_file.write_text(verified_code.rstrip() + "\n", encoding="utf-8")

    safe_desc = " ".join(description.split())[:240].replace('"', "'")
    practices_md = "\n".join(f"- {p}" for p in best_practices)
    sources_md = "\n".join(f"- <{u}>" for u in source_urls[:8]) or "- Internal sandbox verification"

    skill_md = f"""---
name: {clean_slug}
description: "{safe_desc}"
---

# {title}

- **Category:** `{category}`
- **Verification:** Passed isolated AST & runtime sandbox execution in GitHub Actions.

## Architectural Summary

{summary.strip()}

## Verified Best Practices

{practices_md}

## Verified Reference Code

See runnable example at [verified_example.py](./examples/verified_example.py).

```python
{verified_code.strip()}
```

## Sources

{sources_md}
"""
    skill_path = skill_dir / "SKILL.md"
    skill_path.write_text(skill_md, encoding="utf-8")

    lines = ["# Learned Skills Index\n", "| Skill | Category | Last Verified (UTC) |", "| :--- | :--- | :--- |"]
    for item in all_skills_meta:
        s = item["topic_slug"]
        lines.append(f"| [{item['title']}](./{s}/SKILL.md) | `{item['category']}` | {item['updated_at'][:10]} |")
    (root / "_index.md").write_text("\n".join(lines) + "\n", encoding="utf-8")

    return skill_path
