from uuid import UUID

from fastapi import APIRouter

from .auth import CurrentUser
from .comparison_models import ComparisonOverview, ComparisonReviewCreate, ComparisonReviewRead
from .comparison_repository import comparison_repository

router = APIRouter(tags=["paper comparisons"])


@router.get("/projects/{project_id}/comparisons", response_model=ComparisonOverview)
async def get_comparisons(project_id: UUID, current_user: CurrentUser):
    return await comparison_repository.get(current_user, project_id)


@router.post("/projects/{project_id}/comparisons", response_model=ComparisonOverview, status_code=202)
async def start_comparisons(project_id: UUID, current_user: CurrentUser):
    return await comparison_repository.start(current_user, project_id)


@router.post("/projects/{project_id}/comparisons/{pair_id}/reviews", response_model=ComparisonReviewRead, status_code=201)
async def review_comparison(project_id: UUID, pair_id: UUID, payload: ComparisonReviewCreate,
                            current_user: CurrentUser):
    return await comparison_repository.review(current_user, project_id, pair_id, payload)
