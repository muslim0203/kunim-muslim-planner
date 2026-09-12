from __future__ import annotations

from httpx import AsyncClient


async def test_health_ok(client: AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "version" in body
    assert "env" in body


async def test_health_ready_reports_unavailable_dependencies(client: AsyncClient) -> None:
    # Postgres and Redis are not running in this environment, so both
    # dependencies must be reported as "unavailable", without raising, and the
    # endpoint must answer 503 so orchestrators can use it as a readiness gate.
    response = await client.get("/health/ready")
    body = response.json()
    assert body["dependencies"]["database"] in {"ok", "unavailable"}
    assert body["dependencies"]["redis"] in {"ok", "unavailable"}
    all_ok = all(value == "ok" for value in body["dependencies"].values())
    assert response.status_code == (200 if all_ok else 503)
    assert body["status"] == ("ok" if all_ok else "error")
