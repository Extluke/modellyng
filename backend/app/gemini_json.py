"""Pemanggilan Gemini dengan jawaban JSON terstruktur.

Dipakai fitur AI tingkat project (peta alur riset di Maps dan sintesis di
Matriks). Model utama dicoba lebih dulu, lalu model cadangan. Kegagalan
dilaporkan sebagai AiUnavailableError dengan pesan yang bisa dibaca pengguna.
"""

from __future__ import annotations

import logging
from typing import TypeVar

from google import genai
from google.genai import types
from pydantic import BaseModel

from .config import get_settings

logger = logging.getLogger(__name__)

ModelT = TypeVar("ModelT", bound=BaseModel)


class AiUnavailableError(RuntimeError):
    """Gemini tidak dapat menyusun jawaban (kunci, kuota, jaringan, atau isi)."""


class AiInputError(ValueError):
    """Data project belum cukup untuk diproses AI (dipetakan ke HTTP 409)."""


def generate_structured(
    prompt: str,
    schema: type[ModelT],
    *,
    purpose: str,
    failure_message: str,
    temperature: float = 0.2,
    timeout_ms: int = 90_000,
) -> tuple[ModelT, str]:
    """Kembalikan (jawaban tervalidasi, nama model yang dipakai)."""
    settings = get_settings()
    if not settings.gemini_api_key:
        raise AiUnavailableError("Gemini API key belum dikonfigurasi di backend.")

    client = genai.Client(
        api_key=settings.gemini_api_key,
        http_options=types.HttpOptions(timeout=timeout_ms),
    )
    models = list(
        dict.fromkeys(filter(None, [settings.gemini_model, settings.gemini_fallback_model]))
    )
    last_error: Exception | None = None
    for model in models:
        try:
            response = client.models.generate_content(
                model=model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_json_schema=schema.model_json_schema(),
                    temperature=temperature,
                ),
            )
            return schema.model_validate_json(response.text or ""), model
        except Exception as exc:  # noqa: BLE001 - coba model cadangan berikutnya
            logger.warning("%s generation failed on %s: %s", purpose, model, exc)
            last_error = exc
    raise AiUnavailableError(friendly_ai_error(last_error, failure_message))


def friendly_ai_error(exc: Exception | None, failure_message: str) -> str:
    message = str(exc or "")
    upper = message.upper()
    if "429" in message or "RESOURCE_EXHAUSTED" in upper:
        return "Kuota Gemini sedang habis. Coba lagi beberapa saat lagi."
    if any(
        marker in upper
        for marker in ("503", "504", "UNAVAILABLE", "DEADLINE", "TIMEOUT", "TIMED OUT")
    ):
        return "Gemini sedang sibuk atau timeout. Coba lagi beberapa saat lagi."
    if "API_KEY" in upper or "401" in message or "403" in message:
        return "Gemini API key ditolak. Periksa konfigurasi backend."
    return failure_message
