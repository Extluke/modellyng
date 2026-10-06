def test_normalize_gap_type():
    from app.ai_extraction import normalize_gap_type
    assert normalize_gap_type("Methodological") == "methodological"
    assert normalize_gap_type("dataset gap") == "dataset_gap"
    assert normalize_gap_type("ngawur") == None
    print("normalize OK")

def test_validate_evidence():
    from app.ai_extraction import validate_evidence
    paper = "This is a random paper text with some future work: we need to test more."
    assert validate_evidence(paper, "we need to test more.", 1) == True
    assert validate_evidence(paper, "this is totally made up", 1) == False
    assert validate_evidence(paper, "", 1) == False
    print("validate OK")

if __name__ == '__main__':
    test_normalize_gap_type()
    test_validate_evidence()
