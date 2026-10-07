import sys
import os

target = os.path.join("backend", "app", "processing_repository.py")
with open(target, "r", encoding="utf-8") as f:
    content = f.read()

content = content.replace(
    'label = g["statement"][:200]',
    'label = g["statement"]'
)

content = content.replace(
    'label = entity[:200]',
    'label = entity'
)

with open(target, "w", encoding="utf-8") as f:
    f.write(content)
print("Updated processing_repository.py to remove 200 character truncation")
