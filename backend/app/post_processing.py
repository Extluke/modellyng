import uuid
from typing import Any
import logging

from app.saturation import update_saturation_for_project
from app.clustering import update_clusters_for_project
from app.layout import update_layout_for_project

logger = logging.getLogger(__name__)

def run_post_processing(project_id: uuid.UUID) -> None:
    """
    Runs the post processing steps in strict order:
    1. Saturation (Calculates zones based on counts)
    2. Clustering (Calculates semantic clusters)
    3. Layout (Calculates X, Y using spring_layout per zone)
    4. Zones (Can be computed dynamically from the DB coordinates when requested, 
       so no DB save is strictly required here for zones unless there is a table for it).
    """
    logger.info(f"Starting post-processing for project {project_id}")
    
    # We omit Edge calculation here since edges are extracted and saved per paper 
    # prior to this post-processing hook being called.
    
    logger.info("Step 1/3: Updating Saturation")
    update_saturation_for_project(project_id)
    
    logger.info("Step 2/3: Updating Clusters")
    update_clusters_for_project(project_id)
    
    logger.info("Step 3/3: Updating Layout (X, Y)")
    update_layout_for_project(project_id)
    
    logger.info(f"Post-processing complete for project {project_id}")
