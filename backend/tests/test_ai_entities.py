import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.ai_extraction import parse_entities_v2

def test_parse_entities_v2_valid():
    raw = '{"variables": ["A", "B"], "methods": ["C"], "results": []}'
    res = parse_entities_v2(raw)
    assert res == {"variables": ["A", "B"], "methods": ["C"], "results": []}
    print("Valid JSON: OK")

def test_parse_entities_v2_markdown():
    raw = '```json\n{"variables": ["A"], "methods": [], "results": ["B"]}\n```'
    res = parse_entities_v2(raw)
    assert res == {"variables": ["A"], "methods": [], "results": ["B"]}
    print("Markdown JSON: OK")

def test_parse_entities_v2_garbage():
    raw = 'this is not json'
    res = parse_entities_v2(raw)
    assert res == {"variables": [], "methods": [], "results": []}
    print("Garbage JSON: OK")

if __name__ == '__main__':
    test_parse_entities_v2_valid()
    test_parse_entities_v2_markdown()
    test_parse_entities_v2_garbage()
    print("All tests passed!")
