"""Conservative source locators from searchable PDF text, never invented labels."""
import re

from .schemas import EvidenceKind


_HEADING = re.compile(r"^(\d+(?:\.\d+)*)(?:\.?\s+)\S.*$")
_NAMED = re.compile(r"^(?:abstract|introduction|background|methods?|methodology|results?(?: and discussion)?|discussion|conclusions?|references|acknowledg[e]?ments?|pendahuluan|metodologi|metode penelitian|hasil(?: dan pembahasan)?|pembahasan|kesimpulan|daftar pustaka)$", re.I)
_LABELS = {
    EvidenceKind.TABLE: re.compile(r"\b(?:Table|Tabel)\s+\d+[A-Za-z]?\b", re.I),
    EvidenceKind.FIGURE: re.compile(r"\b(?:Figure|Fig\.?|Gambar)\s+\d+[A-Za-z]?\b", re.I),
    EvidenceKind.EQUATION: re.compile(r"\b(?:Equation|Eq\.?|Persamaan)\s*\(?\d+[A-Za-z]?\)?", re.I),
}


def locate_headings(blocks: list[dict], target_id: str, quote: str) -> tuple[str | None, str | None]:
    section = subsection = None
    for block in sorted(blocks, key=lambda b: (int(b["page_number"]), int(b["block_index"]))):
        content = str(block["content"])
        target = str(block["id"]) == target_id
        if target:
            idx = content.find(quote)
            if idx != -1:
                content = content[:idx]
        for raw_line in content.splitlines():
            line = raw_line.strip()
            numbered = _HEADING.fullmatch(line)
            if not line or len(line) > 120 or line.endswith((".", ";", ":", "?")):
                continue
            if numbered and not re.match(r"\d{4}\s", line):
                if "." in numbered[1]:
                    subsection = line
                else:
                    section, subsection = line, None
            elif _NAMED.fullmatch(line):
                section, subsection = line, None
        if target:
            break
    return section, subsection


def classify_evidence(kind: EvidenceKind, label: str | None, quote: str, *, parameter: str) -> tuple[EvidenceKind, str | None]:
    """Specialized labels must occur in the verified quote itself.

    Captions/references identify a source object, not automatic understanding of
    its pixels or mathematical correctness. Human review uses the private PDF.
    """
    pattern = _LABELS.get(kind)
    if pattern:
        matches = list(pattern.finditer(quote))
        for match in matches:
            if label is None or re.sub(r"\s+", "", match[0]).casefold() == re.sub(r"\s+", "", label).casefold():
                return kind, match[0]
        # Equations often have only a literal numbered marker next to a formula.
        if kind == EvidenceKind.EQUATION and label and re.fullmatch(r"\(\d+[A-Za-z]?\)", label) and label in quote and "=" in quote:
            return kind, label
        return EvidenceKind.TEXT, None
    if kind == EvidenceKind.RESULT and parameter != "results_findings":
        return EvidenceKind.TEXT, None
    return kind, None


def partition_blocks_by_route(blocks: list[dict]) -> dict[str, list[dict]]:
    """Partition blocks into intro, method, and discussion routes based on headings."""
    routes = {"intro": [], "method": [], "discussion": []}
    current_route = "intro" # Default start
    
    for block in sorted(blocks, key=lambda b: (int(b.get("page_number", 0)), int(b.get("block_index", 0)))):
        content = str(block.get("content", ""))
        # Simple heuristic to detect section changes
        lower_content = content.lower()
        if re.search(r"^(?:\d+\.\s*)?(?:methods?|methodology|metodologi|metode penelitian)", lower_content, re.MULTILINE):
            current_route = "method"
        elif re.search(r"^(?:\d+\.\s*)?(?:results?|discussion|conclusions?|hasil|pembahasan|kesimpulan)", lower_content, re.MULTILINE):
            current_route = "discussion"
        
        routes[current_route].append(block)
        
    return routes


