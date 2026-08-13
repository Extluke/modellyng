from uuid import UUID

from fastapi import APIRouter, FastAPI, status
from fastapi.middleware.cors import CORSMiddleware

from .config import get_settings
from .repository import EntityNotFoundError, repository
from .schemas import (
    AnalysisJobCreate,
    AnalysisJobRead,
    HealthRead,
    PaperCreate,
    PaperRead,
    ProjectCreate,
    ProjectRead,
)

settings = get_settings()
app = FastAPI(
    title=settings.app_name,
    version="0.1.0",
    description=(
        "API contract for evidence-centered paper extraction, comparison, "
        "research-gap detection, and human review."
    ),
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(EntityNotFoundError)
async def entity_not_found_handler(_, exc: EntityNotFoundError):
    from fastapi.responses import JSONResponse

    return JSONResponse(status_code=404, content={"detail": str(exc)})


@app.get("/health", response_model=HealthRead, tags=["system"])
def health() -> HealthRead:
    return HealthRead(status="ok", service="modellyng-api", version="0.1.0")


router = APIRouter(prefix=settings.api_prefix)


@router.post(
    "/projects",
    response_model=ProjectRead,
    status_code=status.HTTP_201_CREATED,
    tags=["projects"],
)
def create_project(payload: ProjectCreate) -> ProjectRead:
    return repository.create_project(payload)


@router.get("/projects", response_model=list[ProjectRead], tags=["projects"])
def list_projects() -> list[ProjectRead]:
    return repository.list_projects()


@router.get("/projects/{project_id}", response_model=ProjectRead, tags=["projects"])
def get_project(project_id: UUID) -> ProjectRead:
    return repository.get_project(project_id)


@router.post(
    "/projects/{project_id}/papers",
    response_model=PaperRead,
    status_code=status.HTTP_201_CREATED,
    tags=["papers"],
)
def create_paper(project_id: UUID, payload: PaperCreate) -> PaperRead:
    return repository.create_paper(project_id, payload)


@router.get(
    "/projects/{project_id}/papers",
    response_model=list[PaperRead],
    tags=["papers"],
)
def list_papers(project_id: UUID) -> list[PaperRead]:
    return repository.list_papers(project_id)


@router.post(
    "/projects/{project_id}/analysis-jobs",
    response_model=AnalysisJobRead,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["analysis"],
)
def create_analysis_job(
    project_id: UUID, payload: AnalysisJobCreate
) -> AnalysisJobRead:
    job = repository.create_job(project_id, payload)
    if settings.enqueue_jobs:
        from .celery_app import celery_app

        celery_app.send_task("modellyng.run_analysis", args=[str(job.id)], task_id=str(job.id))
    return job


@router.get(
    "/analysis-jobs/{job_id}",
    response_model=AnalysisJobRead,
    tags=["analysis"],
)
def get_analysis_job(job_id: UUID) -> AnalysisJobRead:
    job = repository.get_job(job_id)
    if not settings.enqueue_jobs:
        return job

    from .celery_app import celery_app
    from .schemas import JobStatus

    result = celery_app.AsyncResult(str(job_id))
    if result.state == "PROGRESS":
        metadata = result.info or {}
        return job.model_copy(
            update={
                "status": JobStatus.PROCESSING,
                "stage": metadata.get("stage", "processing"),
                "progress": metadata.get("progress", job.progress),
            }
        )
    if result.state == "SUCCESS":
        return job.model_copy(
            update={"status": JobStatus.COMPLETED, "stage": "completed", "progress": 1}
        )
    if result.state == "FAILURE":
        return job.model_copy(
            update={
                "status": JobStatus.FAILED,
                "stage": "failed",
                "error_message": str(result.info),
            }
        )
    return job


app.include_router(router)


@app.get("/", include_in_schema=False)
def api_root() -> dict[str, str]:
    return {"service": "Modellyng API", "docs": "/docs", "health": "/health"}
