from uuid import UUID

from fastapi import APIRouter, FastAPI, File, HTTPException, UploadFile, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .auth import CurrentUser
from .config import get_settings
from .health import dependency_health
from .repository import (
    EntityNotFoundError,
    InvalidReviewError,
    InvalidUploadError,
    RepositoryError,
    project_repository,
)
from .schemas import (
    DependencyHealthRead,
    HealthRead,
    PaperCreate,
    PaperRead,
    ProjectCreate,
    ProjectRead,
    ReviewQueueItemRead,
    ReviewRecordCreate,
    ReviewRecordRead,
)

settings = get_settings()
MAX_PDF_SIZE_BYTES = 50 * 1024 * 1024
PDF_READ_CHUNK_BYTES = 1024 * 1024

app = FastAPI(
    title=settings.app_name,
    description="Local API for the AI-assisted PDF extraction MVP.",
    version="0.1.0",
)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(EntityNotFoundError)
async def entity_not_found_handler(_, exc: EntityNotFoundError) -> JSONResponse:
    return JSONResponse(status_code=404, content={"detail": str(exc)})


@app.exception_handler(RepositoryError)
async def repository_error_handler(_, exc: RepositoryError) -> JSONResponse:
    return JSONResponse(status_code=502, content={"detail": str(exc)})


@app.exception_handler(InvalidUploadError)
async def invalid_upload_handler(_, exc: InvalidUploadError) -> JSONResponse:
    return JSONResponse(status_code=400, content={"detail": str(exc)})


@app.exception_handler(InvalidReviewError)
async def invalid_review_handler(_, exc: InvalidReviewError) -> JSONResponse:
    return JSONResponse(status_code=409, content={"detail": str(exc)})


@app.get("/health", response_model=HealthRead, tags=["system"])
async def health() -> HealthRead:
    """Return a lightweight liveness response for local development."""
    return HealthRead(status="ok", service="modellyng-api", version="0.1.0")


@app.get(
    "/health/dependencies",
    response_model=DependencyHealthRead,
    tags=["system"],
)
async def health_dependencies() -> DependencyHealthRead:
    """Check whether Redis and local Supabase are reachable from the API."""
    return await dependency_health()


api = APIRouter(prefix=settings.api_prefix)


@api.post(
    "/projects",
    response_model=ProjectRead,
    status_code=status.HTTP_201_CREATED,
    tags=["projects"],
)
async def create_project(
    payload: ProjectCreate,
    current_user: CurrentUser,
) -> ProjectRead:
    return await project_repository.create_project(current_user, payload)


@api.get("/projects", response_model=list[ProjectRead], tags=["projects"])
async def list_projects(current_user: CurrentUser) -> list[ProjectRead]:
    return await project_repository.list_projects(current_user)


@api.get(
    "/projects/{project_id}",
    response_model=ProjectRead,
    tags=["projects"],
)
async def get_project(
    project_id: UUID,
    current_user: CurrentUser,
) -> ProjectRead:
    return await project_repository.get_project(current_user, project_id)


@api.post(
    "/projects/{project_id}/papers",
    response_model=PaperRead,
    status_code=status.HTTP_201_CREATED,
    tags=["papers"],
)
async def create_paper(
    project_id: UUID,
    payload: PaperCreate,
    current_user: CurrentUser,
) -> PaperRead:
    return await project_repository.create_paper(current_user, project_id, payload)


@api.post(
    "/projects/{project_id}/papers/upload",
    response_model=PaperRead,
    status_code=status.HTTP_201_CREATED,
    tags=["papers"],
)
async def upload_paper(
    project_id: UUID,
    current_user: CurrentUser,
    file: UploadFile = File(...),
) -> PaperRead:
    """Receive a PDF through FastAPI, then store it with the user's RLS token."""
    filename = file.filename or ""
    content = bytearray()
    try:
        while chunk := await file.read(PDF_READ_CHUNK_BYTES):
            content.extend(chunk)
            if len(content) > MAX_PDF_SIZE_BYTES:
                raise HTTPException(
                    status_code=status.HTTP_413_CONTENT_TOO_LARGE,
                    detail="Ukuran PDF melebihi batas 50 MB per file",
                )
    finally:
        await file.close()

    return await project_repository.upload_pdf(
        current_user,
        project_id,
        original_filename=filename,
        content=bytes(content),
    )


@api.get(
    "/projects/{project_id}/papers",
    response_model=list[PaperRead],
    tags=["papers"],
)
async def list_papers(
    project_id: UUID,
    current_user: CurrentUser,
) -> list[PaperRead]:
    return await project_repository.list_papers(current_user, project_id)


@api.post(
    "/projects/{project_id}/papers/{paper_id}/process",
    response_model=PaperRead,
    status_code=status.HTTP_202_ACCEPTED,
    tags=["papers"],
)
async def process_paper(
    project_id: UUID,
    paper_id: UUID,
    current_user: CurrentUser,
) -> PaperRead:
    """Queue local PDF extraction or return the already active job."""
    return await project_repository.start_pdf_processing(
        current_user,
        project_id,
        paper_id,
    )


@api.get(
    "/reviews",
    response_model=list[ReviewQueueItemRead],
    tags=["reviews"],
)
async def list_reviews(current_user: CurrentUser) -> list[ReviewQueueItemRead]:
    return await project_repository.list_review_queue(current_user)


@api.post(
    "/reviews/{component_id}",
    response_model=ReviewRecordRead,
    status_code=status.HTTP_201_CREATED,
    tags=["reviews"],
)
async def review_component(
    component_id: UUID,
    payload: ReviewRecordCreate,
    current_user: CurrentUser,
) -> ReviewRecordRead:
    return await project_repository.review_component(
        current_user,
        component_id,
        payload,
    )


app.include_router(api)
