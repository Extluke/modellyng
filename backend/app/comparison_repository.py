import asyncio
import logging
from uuid import UUID

import httpx

from .auth import AuthenticatedUser
from .comparison_models import ComparisonOverview, ComparisonReviewCreate, ComparisonReviewRead
from .config import get_settings
from .repository import EntityNotFoundError, InvalidReviewError, RepositoryError, project_repository

logger = logging.getLogger(__name__)


class ComparisonRepository:
    async def _rpc(self, user: AuthenticatedUser, name: str, payload: dict):
        settings = get_settings()
        try:
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.post(
                    f"{settings.supabase_url.rstrip('/')}/rest/v1/rpc/{name}",
                    headers={"apikey": settings.supabase_anon_key, "Authorization": f"Bearer {user.access_token}"},
                    json=payload,
                )
        except httpx.HTTPError:
            raise RepositoryError("Database perbandingan belum dapat dihubungi. Coba lagi nanti.") from None
        if response.is_error:
            try:
                code = response.json().get("code")
            except ValueError:
                code = None
            if code == "P0002":
                raise EntityNotFoundError("Proyek atau pasangan paper tidak ditemukan")
            if code in {"22023", "23514"}:
                raise InvalidReviewError("Kandidat sudah berubah atau keputusan review tidak valid. Muat ulang analisis.")
            raise RepositoryError("Layanan perbandingan belum tersedia. Periksa koneksi dan migrasi database.")
        return response.json()

    async def get(self, user: AuthenticatedUser, project_id: UUID) -> ComparisonOverview:
        data = await self._rpc(user, "get_project_comparisons", {"p_project_id": str(project_id)})
        return ComparisonOverview.model_validate(data)

    async def start(self, user: AuthenticatedUser, project_id: UUID, *, retry: bool = True) -> ComparisonOverview:
        data = await self._rpc(user, "sync_project_comparisons", {"p_project_id": str(project_id), "p_retry": retry})
        overview = ComparisonOverview.model_validate(data)
        queued = [p for p in overview.pairs if p.status == "queued"]
        if not queued:
            return overview
        if not get_settings().enqueue_jobs:
            overview.dispatch_warning = "Antrean worker dinonaktifkan. Aktifkan worker lalu coba lagi."
            return overview
        from .comparison_tasks import analyze_paper_pair
        try:
            for pair in queued:
                await asyncio.to_thread(analyze_paper_pair.apply_async, args=[str(pair.id)], retry=False)
        except Exception:
            overview.dispatch_warning = "Sebagian analisis belum terkirim ke worker. Klik Analisis / coba lagi untuk melanjutkan."
        return overview

    async def review(self, user: AuthenticatedUser, project_id: UUID, pair_id: UUID,
                     payload: ComparisonReviewCreate) -> ComparisonReviewRead:
        overview = await self.get(user, project_id)
        if not any(p.id == pair_id for p in overview.pairs):
            raise InvalidReviewError("Pasangan ini bukan hasil terkini proyek. Muat ulang analisis.")
        data = await self._rpc(user, "review_paper_comparison", {
            "p_pair_id": str(pair_id), "p_decision": payload.decision, "p_note": payload.note,
        })
        return ComparisonReviewRead.model_validate(data)


comparison_repository = ComparisonRepository()


async def queue_reviewed_comparisons(user: AuthenticatedUser, component_ids: list[UUID]) -> None:
    """Publish Celery work after successful reviews; never undo a saved review.

    A broker outage leaves durable queued rows. The UI can safely publish them
    again; a database claim prevents duplicate model calls.
    """
    try:
        settings = get_settings()
        async with httpx.AsyncClient(timeout=15) as client:
            response = await client.get(
                f"{settings.supabase_url.rstrip('/')}/rest/v1/extracted_components",
                headers=project_repository._headers(user),
                params={"select": "papers(project_id)", "id": "in.(" + ",".join(map(str, component_ids)) + ")"},
            )
        response.raise_for_status()
        project_ids = {row["papers"]["project_id"] for row in response.json() if row.get("papers")}
        for project_id in project_ids:
            await comparison_repository.start(user, UUID(project_id), retry=False)
    except Exception:
        logger.warning("Automatic comparison scheduling unavailable; manual retry remains available.")
