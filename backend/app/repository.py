from datetime import UTC, datetime
from threading import Lock
from uuid import UUID, uuid4

from .schemas import (
    AnalysisJobCreate,
    AnalysisJobRead,
    JobStatus,
    PaperCreate,
    PaperRead,
    PaperStatus,
    ProjectCreate,
    ProjectRead,
    ProjectStatus,
)


class EntityNotFoundError(LookupError):
    pass


class InMemoryRepository:
    """Development adapter that preserves the production API contract.

    The PostgreSQL migration in ``migrations/0001_initial.sql`` is the source
    of truth for persistent storage. This adapter lets the API and Flutter
    integration run before infrastructure credentials are configured.
    """

    def __init__(self) -> None:
        self._projects: dict[UUID, ProjectRead] = {}
        self._papers: dict[UUID, PaperRead] = {}
        self._jobs: dict[UUID, AnalysisJobRead] = {}
        self._lock = Lock()

    def create_project(self, payload: ProjectCreate) -> ProjectRead:
        now = datetime.now(UTC)
        project = ProjectRead(
            id=uuid4(),
            title=payload.title,
            description=payload.description,
            status=ProjectStatus.READY,
            paper_count=0,
            created_at=now,
            updated_at=now,
        )
        with self._lock:
            self._projects[project.id] = project
        return project

    def list_projects(self) -> list[ProjectRead]:
        with self._lock:
            return sorted(
                self._projects.values(),
                key=lambda project: project.updated_at,
                reverse=True,
            )

    def get_project(self, project_id: UUID) -> ProjectRead:
        with self._lock:
            project = self._projects.get(project_id)
        if project is None:
            raise EntityNotFoundError(f"Project {project_id} was not found")
        return project

    def create_paper(self, project_id: UUID, payload: PaperCreate) -> PaperRead:
        project = self.get_project(project_id)
        paper = PaperRead(
            id=uuid4(),
            project_id=project_id,
            status=PaperStatus.VALIDATING,
            created_at=datetime.now(UTC),
            **payload.model_dump(),
        )
        with self._lock:
            self._papers[paper.id] = paper
            self._projects[project_id] = project.model_copy(
                update={
                    "paper_count": project.paper_count + 1,
                    "updated_at": datetime.now(UTC),
                }
            )
        return paper

    def list_papers(self, project_id: UUID) -> list[PaperRead]:
        self.get_project(project_id)
        with self._lock:
            return [
                paper for paper in self._papers.values() if paper.project_id == project_id
            ]

    def create_job(
        self, project_id: UUID, payload: AnalysisJobCreate
    ) -> AnalysisJobRead:
        project = self.get_project(project_id)
        project_paper_ids = {paper.id for paper in self.list_papers(project_id)}
        missing = set(payload.paper_ids) - project_paper_ids
        if missing:
            raise EntityNotFoundError(
                f"Papers do not belong to project {project_id}: {sorted(map(str, missing))}"
            )
        now = datetime.now(UTC)
        job = AnalysisJobRead(
            id=uuid4(),
            project_id=project_id,
            paper_ids=payload.paper_ids,
            parameters=payload.parameters,
            status=JobStatus.QUEUED,
            stage="queued",
            progress=0,
            created_at=now,
            updated_at=now,
        )
        with self._lock:
            self._jobs[job.id] = job
            self._projects[project_id] = project.model_copy(
                update={"status": ProjectStatus.PROCESSING, "updated_at": now}
            )
        return job

    def get_job(self, job_id: UUID) -> AnalysisJobRead:
        with self._lock:
            job = self._jobs.get(job_id)
        if job is None:
            raise EntityNotFoundError(f"Analysis job {job_id} was not found")
        return job


repository = InMemoryRepository()
