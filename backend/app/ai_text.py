"""Utilitas teks bersama untuk fitur AI tingkat project (peta alur, sintesis)."""

from __future__ import annotations

import json
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


# --- Nilai komponen berbentuk JSON -------------------------------------------
# Beberapa komponen (terutama future_work) disimpan sebagai JSON agar bisa
# diurai menjadi tabel. Untuk dibaca manusia, JSON itu diubah menjadi teks
# biasa. Isi tidak ditambah atau diubah; hanya struktur teknisnya yang dirapikan.

_CODE_FENCE = re.compile(r"^```[\w-]*[ \t]*\n?|\n?```\s*$")
_LOOSE_JSON_KEY = re.compile(r'"([^"\n]{1,60})"\s*:\s*')
_JSON_PUNCTUATION = re.compile(r"[{}\[\]]")
_DEVELOPMENT_KEYS = ("pengembangan", "arah_pengembangan")
_RECOMMENDATION_TITLE_KEYS = ("judul", "judul_rekomendasi", "title", "idea", "ide")
_RECOMMENDATION_FIELDS = (
    ("Alasan", ("alasan", "alasan_konteks", "rationale", "reason")),
    ("Metode", ("metode", "method", "methodology")),
    ("Dampak", ("dampak", "impact")),
)
_RECOMMENDATION_KNOWN_KEYS = {
    "rank",
    *_RECOMMENDATION_TITLE_KEYS,
    *(key for _, keys in _RECOMMENDATION_FIELDS for key in keys),
}


def readable_component_value(value: object) -> str:
    """Ubah nilai komponen berbentuk JSON menjadi teks yang enak dibaca.

    Nilai yang bukan JSON dikembalikan apa adanya. JSON yang rusak tetap
    dirapikan dengan membuang tanda kurung dan tanda kutip teknisnya.
    """
    text = str(value or "").strip()
    body = _CODE_FENCE.sub("", text).strip()
    if not body or body[0] not in "{[":
        return text
    try:
        data = json.loads(body)
    except ValueError:
        return _loosen_json_text(body)
    return "\n".join(_render_json(data, "")).strip()


def _is_empty(value: object) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        return not value.strip()
    if isinstance(value, (list, dict)):
        return not value
    return False


def _humanize_key(key: object) -> str:
    words = str(key).replace("_", " ").replace("-", " ").strip()
    return words[:1].upper() + words[1:] if words else ""


def _scalar(value: object) -> str:
    if isinstance(value, bool):
        return "Ya" if value else "Tidak"
    if isinstance(value, (dict, list)):
        parts = [line.strip().lstrip("•").strip() for line in _render_json(value, "")]
        return "; ".join(part for part in parts if part)
    return str(value).strip()


def _first_present(data: dict, keys: Iterable[str]) -> object | None:
    for key in keys:
        if not _is_empty(data.get(key)):
            return data[key]
    return None


def _render_json(data: object, indent: str) -> list[str]:
    if _is_empty(data):
        return []
    if isinstance(data, dict):
        if "recommendations" in data or any(key in data for key in _DEVELOPMENT_KEYS):
            return _render_future_work(data, indent)
        return _render_mapping(data, indent, skip=set())
    if isinstance(data, list):
        lines: list[str] = []
        for item in data:
            if _is_empty(item):
                continue
            if isinstance(item, (dict, list)):
                inner = _render_json(item, indent + "  ")
                if inner:
                    lines.append(f"{indent}• {inner[0].strip()}")
                    lines.extend(inner[1:])
            else:
                lines.append(f"{indent}• {_scalar(item)}")
        return lines
    return [f"{indent}{_scalar(data)}"]


def _render_mapping(data: dict, indent: str, *, skip: set[str]) -> list[str]:
    lines: list[str] = []
    for key, value in data.items():
        if key in skip or _is_empty(value):
            continue
        label = _humanize_key(key)
        if isinstance(value, (dict, list)):
            lines.append(f"{indent}{label}:")
            lines.extend(_render_json(value, indent + "  "))
        else:
            lines.append(f"{indent}{label}: {_scalar(value)}")
    return lines


def _render_future_work(data: dict, indent: str) -> list[str]:
    lines: list[str] = []
    development = _first_present(data, _DEVELOPMENT_KEYS)
    if development is not None:
        lines.extend(_render_json(development, indent))
    recommendations = data.get("recommendations")
    if isinstance(recommendations, list):
        for index, item in enumerate(recommendations, start=1):
            if _is_empty(item):
                continue
            if lines:
                lines.append("")
            if not isinstance(item, dict):
                lines.append(f"{indent}{index}. {_scalar(item)}")
                continue
            rank = item.get("rank") if not _is_empty(item.get("rank")) else index
            title = _first_present(item, _RECOMMENDATION_TITLE_KEYS)
            lines.append(
                f"{indent}{_scalar(rank)}. {_scalar(title) if title is not None else 'Rekomendasi'}"
            )
            for label, keys in _RECOMMENDATION_FIELDS:
                field_value = _first_present(item, keys)
                if field_value is not None:
                    lines.append(f"{indent}   {label}: {_scalar(field_value)}")
            for key, extra in item.items():
                if key not in _RECOMMENDATION_KNOWN_KEYS and not _is_empty(extra):
                    lines.append(f"{indent}   {_humanize_key(key)}: {_scalar(extra)}")
    elif not _is_empty(recommendations):
        lines.extend(_render_json(recommendations, indent))
    extra_lines = _render_mapping(
        data, indent, skip={"recommendations", *_DEVELOPMENT_KEYS}
    )
    if extra_lines:
        if lines:
            lines.append("")
        lines.extend(extra_lines)
    return lines


def _loosen_json_text(body: str) -> str:
    """JSON yang tidak valid: buang tanda teknis agar isinya tetap terbaca."""
    text = _LOOSE_JSON_KEY.sub(lambda match: f"\n{_humanize_key(match.group(1))}: ", body)
    text = _JSON_PUNCTUATION.sub("\n", text)
    text = text.replace('\\"', "'").replace('"', "")
    lines = [line.strip().strip(",").strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)
