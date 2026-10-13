"""Utilitas teks bersama untuk fitur AI tingkat project (peta alur, sintesis)."""

from __future__ import annotations

import re
from collections.abc import Iterable

PLACEHOLDER_VALUES = {"", "-", "informasi tidak ditemukan", "informasi tidak ditemukan."}

_KEY_PATTERN = re.compile(r"P\s*(\d+)", re.IGNORECASE)
_BARE_NUMBER = re.compile(r"^\D*(\d+)\D*$")
_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")
_METHOD_HEADER = re.compile(r"-{2,}\s*[A-Z ]+\s*-{2,}")


def clean_text(text: object) -> str:
    """Rapatkan spasi dan baris baru menjadi satu spasi."""
    return " ".join(str(text or "").split())


def is_placeholder(text: object) -> bool:
    return clean_text(text).lower() in PLACEHOLDER_VALUES


def normalize_paper_key(raw: object) -> str:
    """"p1", "[P1]", "Paper 1", atau "1" menjadi "P1"; selain itu string kosong."""
    text = str(raw or "")
    match = _KEY_PATTERN.search(text) or _BARE_NUMBER.match(text)
    return f"P{int(match.group(1))}" if match else ""


def unique_paper_keys(raw_keys: Iterable[object]) -> list[str]:
    keys: list[str] = []
    for raw in raw_keys:
        key = normalize_paper_key(raw)
        if key and key not in keys:
            keys.append(key)
    return keys


def shorten(text: object, limit: int) -> str:
    """Potong di batas kata agar tidak melebihi [limit] karakter."""
    value = clean_text(text).strip(" .;,")
    if value.lower() in PLACEHOLDER_VALUES:
        return ""
    if len(value) <= limit:
        return value
    cut = value[: limit - 1]
    if " " in cut:
        cut = cut.rsplit(" ", 1)[0]
    return cut.rstrip(" .;,") + "…"


def first_sentence(text: object) -> str:
    """Kalimat pertama; header metodologi hasil ekstraksi dilewati."""
    value = clean_text(text)
    if "ARAH KEGIATAN" in value:
        value = value.split("ARAH KEGIATAN", 1)[1]
    value = clean_text(_METHOD_HEADER.sub(" ", value)).strip(" -:")
    return _SENTENCE_END.split(value, 1)[0] if value else ""
