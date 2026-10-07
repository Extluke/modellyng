import pytest
from app.layout import compute_layout, compute_zones, ZONE_BOUNDS

def test_compute_layout_and_zones():
    nodes = [
        {"id": "n1", "saturation_status": "none"},
        {"id": "n2", "saturation_status": "none"},
        {"id": "n3", "saturation_status": "low"},
        {"id": "n4", "saturation_status": "low"},
        {"id": "n5", "saturation_status": "medium"},
        {"id": "n6", "saturation_status": "high"},
    ]
    edges = [
        {"source": "n1", "target": "n2"},
        {"source": "n3", "target": "n4"},
    ]
    
    layout = compute_layout(nodes, edges)
    
    assert len(layout) == 6
    
    # Assign coordinates back to nodes for zone computation
    for n in nodes:
        x, y = layout[n["id"]]
        n["x"] = x
        n["y"] = y
        
    zones = compute_zones(nodes)
    
    # Check that there are 4 zones generated (none, low, medium, high)
    assert len(zones) == 4
    
    # Check that zones do not overlap on the X axis
    # none: 0-400, low: 500-900, medium: 1000-1400, high: 1500-1900
    # Because of padding (20), bounds will expand slightly. 
    # Max overlap check:
    
    sorted_zones = sorted(zones, key=lambda z: z["min_x"])
    for i in range(len(sorted_zones) - 1):
        z1 = sorted_zones[i]
        z2 = sorted_zones[i+1]
        
        # Right edge of z1 must be strictly less than left edge of z2
        assert z1["max_x"] < z2["min_x"], f"Overlap detected between {z1['saturation_status']} and {z2['saturation_status']}"

def test_identical_coordinates_fallback():
    # If nodes have no edges, spring_layout might place them in the center.
    # We must ensure they don't get exact identical coordinates.
    nodes = [
        {"id": f"n{i}", "saturation_status": "high"} for i in range(10)
    ]
    
    layout = compute_layout(nodes, [])
    coords = list(layout.values())
    
    # All coords must be unique
    assert len(coords) == len(set(coords)), "Duplicate coordinates found!"

def test_empty_graph():
    assert compute_layout([], []) == {}
    assert compute_zones([]) == []
