from __future__ import annotations

import asyncio
import os
import random
import time
from dataclasses import dataclass

import httpx
from bs4 import BeautifulSoup
from markdownify import markdownify as to_markdown

try:
    from ddgs import DDGS
except ImportError:
    from duckduckgo_search import DDGS


@dataclass
class ResearchBundle:
    urls: list[str]
    combined_markdown: str


def search_web_ddg(query: str, max_results: int = 5) -> list[dict[str, str]]:
    """Free DuckDuckGo search with polite jitter to avoid rate limits."""
    time.sleep(random.uniform(0.8, 1.8))
    results: list[dict[str, str]] = []
    with DDGS() as ddgs:
        for item in ddgs.text(query, max_results=max_results):
            url = item.get("href") or item.get("url")
            if url:
                results.append(
                    {
                        "title": item.get("title", ""),
                        "url": url,
                        "snippet": item.get("body", ""),
                    }
                )
    return results


def search_github_repos(query: str, max_repos: int = 3) -> list[str]:
    """Search popular reference repositories via the free GitHub REST API."""
    headers = {"Accept": "application/vnd.github+json"}
    token = os.getenv("GITHUB_TOKEN", "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"

    try:
        resp = httpx.get(
            "https://api.github.com/search/repositories",
            params={"q": f"{query} language:python", "sort": "stars", "per_page": max_repos},
            headers=headers,
            timeout=15.0,
        )
        resp.raise_for_status()
        items = resp.json().get("items", [])
        return [
            f"- Repo `{r['full_name']}` ({r['stargazers_count']}*): {r.get('description') or ''} -> {r['html_url']}"
            for r in items
        ]
    except Exception:
        return []


async def _fetch_with_crawl4ai(urls: list[str], max_chars_per_page: int = 6000) -> dict[str, str]:
    extracted: dict[str, str] = {}
    try:
        from crawl4ai import AsyncWebCrawler, BrowserConfig

        browser_cfg = BrowserConfig(headless=True, verbose=False)
        async with AsyncWebCrawler(config=browser_cfg) as crawler:
            for url in urls:
                try:
                    res = await asyncio.wait_for(crawler.arun(url=url), timeout=25.0)
                    if res.success and res.markdown:
                        extracted[url] = res.markdown[:max_chars_per_page]
                except Exception:
                    continue
    except Exception:
        pass
    return extracted


def _fetch_fallback_httpx(url: str, max_chars: int = 6000) -> str:
    try:
        resp = httpx.get(
            url,
            timeout=12.0,
            follow_redirects=True,
            headers={"User-Agent": "code-architect-engine/1.0 (+research-bot)"},
        )
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header"]):
            tag.decompose()
        main = soup.find("main") or soup.find("article") or soup.body
        md = to_markdown(str(main or soup), heading_style="ATX")
        return md.strip()[:max_chars]
    except Exception:
        return ""


def gather_topic_research(topic: str, max_pages: int = 3) -> ResearchBundle:
    search_hits = search_web_ddg(f"{topic} official documentation python example", max_results=5)
    gh_refs = search_github_repos(topic, max_repos=3)

    target_urls = [h["url"] for h in search_hits[:max_pages]]
    crawled = asyncio.run(_fetch_with_crawl4ai(target_urls)) if target_urls else {}

    sections: list[str] = []
    if gh_refs:
        sections.append("## Top GitHub References\n" + "\n".join(gh_refs))

    for hit in search_hits:
        u = hit["url"]
        body = crawled.get(u)
        if not body and u in target_urls:
            body = _fetch_fallback_httpx(u)
        text = body or hit["snippet"]
        if text:
            sections.append(f"## Source: {hit['title']}\nURL: {u}\n\n{text}")

    return ResearchBundle(
        urls=[h["url"] for h in search_hits],
        combined_markdown="\n\n---\n\n".join(sections)[:24000],
    )
