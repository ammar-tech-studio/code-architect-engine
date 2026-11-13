from __future__ import annotations

import json
import os
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml
from openai import (
    APIConnectionError,
    APIError,
    APITimeoutError,
    AuthenticationError,
    OpenAI,
    RateLimitError,
)


@dataclass
class LLMResponse:
    """Normalized response returned by ModelRouter."""

    content: str
    provider: str
    model: str
    tokens_used: int = 0


class ModelRouter:
    """Unified OpenAI-compatible router with per-session fallback and quota protection."""

    def __init__(self, config_path: str | Path = "config/providers.yaml") -> None:
        raw = yaml.safe_load(Path(config_path).read_text(encoding="utf-8"))
        self.providers_cfg: dict[str, dict[str, Any]] = raw["providers"]
        self.routes: dict[str, list[dict[str, Any]]] = raw["routes"]
        self._clients: dict[str, OpenAI] = {}
        self._disabled_providers: set[str] = set()
        self._disabled_models: set[tuple[str, str]] = set()

    def _get_client(self, provider_name: str) -> OpenAI | None:
        if provider_name in self._disabled_providers:
            return None
        if provider_name in self._clients:
            return self._clients[provider_name]

        cfg = self.providers_cfg.get(provider_name)
        if not cfg:
            return None

        api_key = os.getenv(cfg["api_key_env"], "").strip()
        if not api_key:
            self._disabled_providers.add(provider_name)
            return None

        client = OpenAI(
            base_url=cfg["base_url"],
            api_key=api_key,
            default_headers=cfg.get("extra_headers") or {},
        )
        self._clients[provider_name] = client
        return client

    @staticmethod
    def strip_thinking_tags(text: str) -> str:
        """Remove reasoning tags such as <think>...</think> before parsing outputs."""
        cleaned = re.sub(r"<think>.*?</think>", "", text, flags=re.DOTALL)
        return cleaned.strip()

    @staticmethod
    def extract_json(text: str) -> dict[str, Any]:
        """Extract a valid JSON object even when wrapped in prose or markdown fences."""
        cleaned = ModelRouter.strip_thinking_tags(text)
        # Strip outer ```json ... ``` fence without using non-greedy .*? across nested braces
        if cleaned.startswith("```"):
            cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, count=1)
            cleaned = re.sub(r"\s*```$", "", cleaned, count=1).strip()

        start = cleaned.find("{")
        end = cleaned.rfind("}")
        if start == -1 or end == -1 or end <= start:
            raise ValueError(f"No valid JSON object found in output: {cleaned[:200]}")

        return json.loads(cleaned[start : end + 1])

    def complete(
        self,
        task_type: str,
        messages: list[dict[str, str]],
        temperature: float = 0.2,
        max_tokens: int = 4096,
    ) -> LLMResponse:
        candidates = self.routes.get(task_type) or self.routes["coding"]
        errors: list[str] = []

        for entry in candidates:
            provider = entry["provider"]
            model = entry["model"]
            timeout = float(entry.get("timeout", 60))

            if (provider, model) in self._disabled_models:
                continue

            client = self._get_client(provider)
            if client is None:
                continue

            try:
                resp = client.chat.completions.create(
                    model=model,
                    messages=messages,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    timeout=timeout,
                )
                content = (resp.choices[0].message.content or "").strip()
                if not content:
                    raise ValueError("Empty response from model")

                usage = getattr(resp, "usage", None)
                total_tokens = getattr(usage, "total_tokens", 0) if usage else 0
                return LLMResponse(
                    content=self.strip_thinking_tags(content),
                    provider=provider,
                    model=model,
                    tokens_used=total_tokens or 0,
                )

            except AuthenticationError as exc:
                self._disabled_providers.add(provider)
                errors.append(f"{provider}/{model}: auth error ({exc})")
            except RateLimitError as exc:
                self._disabled_models.add((provider, model))
                errors.append(f"{provider}/{model}: rate limit 429 ({exc})")
                time.sleep(1.0)
            except (APITimeoutError, APIConnectionError, APIError, ValueError) as exc:
                self._disabled_models.add((provider, model))
                errors.append(f"{provider}/{model}: {type(exc).__name__} ({exc})")
                time.sleep(0.5)

        raise RuntimeError(
            f"Failed task ({task_type}) across all available providers:\n" + "\n".join(errors)
        )

    def complete_json(
        self,
        task_type: str,
        messages: list[dict[str, str]],
        temperature: float = 0.1,
        max_tokens: int = 4096,
    ) -> tuple[dict[str, Any], LLMResponse]:
        """Call model and perform one automatic JSON repair retry on parse failure."""
        resp = self.complete(task_type, messages, temperature=temperature, max_tokens=max_tokens)
        try:
            return self.extract_json(resp.content), resp
        except Exception as first_err:
            repair_messages = messages + [
                {"role": "assistant", "content": resp.content},
                {
                    "role": "user",
                    "content": (
                        f"Your previous output could not be parsed as valid JSON ({first_err}). "
                        "Return ONLY a valid raw JSON object matching the requested schema, with no commentary."
                    ),
                },
            ]
            retry_resp = self.complete("fast_json", repair_messages, temperature=0.0, max_tokens=max_tokens)
            return self.extract_json(retry_resp.content), retry_resp
