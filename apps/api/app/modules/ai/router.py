"""HTTP surface for the AI assistant.

Route summary::

    POST  /ai/analysis            201  ProposalOut   (a new proposal)
    GET   /ai/proposals           200  [ProposalOut]
    PATCH /ai/proposals/{id}      200  ProposalOut   (accept / modify / reject)

Every route resolves "which user" through `CurrentUser` alone; no route takes
another user's id, and no route writes to the user's own data. `POST` answers
**503** whenever there is no analysis -- no key, provider down, a refusal, an
answer that failed the religious guard -- because the client's response to
all four is the same: keep showing the analysis it computed itself. The
reason is in the body for the log, not for the user.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.ai.provider import get_provider
from app.ai.usage.limiter import get_daily_quota
from app.core.config import Settings, get_settings
from app.core.deps import CurrentUser
from app.db.session import get_session
from app.modules.ai.repository import AiRepository
from app.modules.ai.schemas import (
    AnalysisRequest,
    ProposalOut,
    ProposalStatusUpdate,
)
from app.modules.ai.service import (
    AiFeatureOff,
    AiNoAnswer,
    AiQuotaExceeded,
    AiService,
    accepted_statuses,
)

router = APIRouter(prefix="/ai", tags=["ai"])


async def get_ai_service(
    session: Annotated[AsyncSession, Depends(get_session)],
    settings: Annotated[Settings, Depends(get_settings)],
) -> AiService:
    return AiService(
        AiRepository(session),
        provider=get_provider(),
        quota=get_daily_quota(),
        daily_limit=settings.AI_DAILY_ANALYSIS_LIMIT,
    )


AiServiceDep = Annotated[AiService, Depends(get_ai_service)]


@router.post(
    "/analysis",
    response_model=ProposalOut,
    status_code=status.HTTP_201_CREATED,
    summary="Analyse what the phone measured and propose what to change",
)
async def propose_analysis(
    payload: AnalysisRequest, user: CurrentUser, service: AiServiceDep
) -> ProposalOut:
    try:
        proposal = await service.propose_analysis(user, payload)
    except AiFeatureOff as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The AI assistant is not configured on this server.",
        ) from exc
    except AiQuotaExceeded as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Today's analyses are used up. Try again tomorrow.",
        ) from exc
    except AiNoAnswer as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"The AI assistant could not answer ({exc.reason}).",
        ) from exc
    return ProposalOut.model_validate(proposal)


@router.get(
    "/proposals",
    response_model=list[ProposalOut],
    summary="The user's own proposals, newest first",
)
async def list_proposals(
    user: CurrentUser,
    service: AiServiceDep,
    agent: Annotated[str | None, Query(max_length=32)] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
) -> list[ProposalOut]:
    proposals = await service.list_proposals(user, agent=agent, limit=limit)
    return [ProposalOut.model_validate(proposal) for proposal in proposals]


@router.patch(
    "/proposals/{proposal_id}",
    response_model=ProposalOut,
    summary="Record that a proposal was accepted, modified or rejected",
)
async def update_proposal(
    proposal_id: uuid.UUID,
    payload: ProposalStatusUpdate,
    user: CurrentUser,
    service: AiServiceDep,
) -> ProposalOut:
    if payload.status not in accepted_statuses():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="A proposal can only be accepted, modified or rejected.",
        )
    updated = await service.update_status(user, proposal_id, payload)
    if updated is None:
        # 404 and not 403: whether a proposal exists for another user is not
        # this user's business.
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Proposal not found.")
    return ProposalOut.model_validate(updated)
