from arq.worker import Worker

from app.jobs.worker import WorkerSettings


async def test_worker_startup_configures_logging() -> None:
    await WorkerSettings.on_startup({})


def test_worker_configuration_can_start() -> None:
    worker = Worker(
        functions=WorkerSettings.functions,
        redis_settings=WorkerSettings.redis_settings,
        handle_signals=False,
    )
    assert "ping" in worker.functions
    assert worker.redis_settings.host
