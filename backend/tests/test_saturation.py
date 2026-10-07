import pytest
from app.saturation import compute_saturation
from app.schemas import SaturationStatus

def test_compute_saturation():
    # 0, total 0
    assert compute_saturation(0, 0) == SaturationStatus.NONE
    
    # 0
    assert compute_saturation(0, 10) == SaturationStatus.NONE
    
    # 1/10 = 0.1 <= 0.20 -> low
    assert compute_saturation(1, 10) == SaturationStatus.LOW
    
    # 2/10 = 0.2 <= 0.20 -> low
    assert compute_saturation(2, 10) == SaturationStatus.LOW
    
    # 3/10 = 0.3 <= 0.50 -> medium
    assert compute_saturation(3, 10) == SaturationStatus.MEDIUM
    
    # 5/10 = 0.5 <= 0.50 -> medium
    assert compute_saturation(5, 10) == SaturationStatus.MEDIUM
    
    # 6/10 = 0.6 > 0.50 -> high
    assert compute_saturation(6, 10) == SaturationStatus.HIGH
