import sys
import os

target = os.path.join("backend", "app", "repository.py")
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace(
    'if nt in ("gap",):',
    'if nt in ("gap", "research_gap"):'
)

content = content.replace(
    'elif nt in ("variable", "method"):',
    'elif nt in ("variable", "method", "object"):'
)

content = content.replace(
    'ALLOWED_GAPS = {"population", "methodological", "empirical", "theoretical", "conceptual", "unexplored_concept", "missing_relation", "dataset", "other"}',
    'ALLOWED_GAPS = {"population_gap", "methodological", "empirical_gap", "theoretical", "conceptual", "unexplored_concept", "missing_relation", "dataset_gap", "other"}'
)

with open(target, "w", encoding="utf-8") as f:
    f.write(content)
print("Updated repository.py successfully")
