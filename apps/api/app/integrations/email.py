"""Sending mail.

One message matters today: the password-reset code.

A provider is optional. Without `RESEND_API_KEY` the app still starts and the
endpoints still answer; the message is recorded as *not sent* instead of
being delivered, and nothing pretends otherwise. That keeps a development or
self-hosted deploy working, and makes a misconfigured production deploy
visible in the logs rather than silently swallowing password resets.

Logs never carry the message body (it holds the code) or the full address:
only the recipient's domain, which is enough to tell "Gmail is bouncing us"
from "nothing is being sent at all".
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

import httpx
import structlog

from app.core.config import Settings, get_settings

logger = structlog.get_logger(__name__)

RESEND_ENDPOINT = "https://api.resend.com/emails"
SEND_TIMEOUT_SECONDS = 10.0


@dataclass(frozen=True)
class EmailMessage:
    to: str
    subject: str
    body: str


def _domain_of(address: str) -> str:
    _, _, domain = address.partition("@")
    return domain or "unknown"


class EmailSender(Protocol):
    async def send(self, message: EmailMessage) -> bool:
        """True when the provider accepted the message."""
        ...


class LoggingEmailSender:
    """Stands in when no provider is configured: records, never delivers."""

    async def send(self, message: EmailMessage) -> bool:
        logger.warning(
            "email_not_sent_no_provider",
            to_domain=_domain_of(message.to),
            subject=message.subject,
        )
        return False


class ResendEmailSender:
    """Sends through Resend's HTTP API."""

    def __init__(
        self,
        *,
        api_key: str,
        sender: str,
        endpoint: str = RESEND_ENDPOINT,
        timeout: float = SEND_TIMEOUT_SECONDS,
    ) -> None:
        self._api_key = api_key
        self._sender = sender
        self._endpoint = endpoint
        self._timeout = timeout

    async def send(self, message: EmailMessage) -> bool:
        payload = {
            "from": self._sender,
            "to": [message.to],
            "subject": message.subject,
            "text": message.body,
        }
        try:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                response = await client.post(
                    self._endpoint,
                    headers={"Authorization": f"Bearer {self._api_key}"},
                    json=payload,
                )
        except httpx.HTTPError as exc:
            # The provider's message can carry the payload back; only the type
            # is logged.
            logger.error(
                "email_send_failed",
                to_domain=_domain_of(message.to),
                error_type=type(exc).__name__,
            )
            return False

        if response.status_code >= 400:
            logger.error(
                "email_send_failed",
                to_domain=_domain_of(message.to),
                status=response.status_code,
            )
            return False
        return True


_sender: EmailSender | None = None


def build_email_sender(settings: Settings) -> EmailSender:
    if settings.RESEND_API_KEY:
        return ResendEmailSender(
            api_key=settings.RESEND_API_KEY,
            sender=settings.EMAIL_FROM,
        )
    return LoggingEmailSender()


def get_email_sender() -> EmailSender:
    """Process-wide sender. Overridable in tests via `set_email_sender`."""
    global _sender
    if _sender is None:
        _sender = build_email_sender(get_settings())
    return _sender


def set_email_sender(sender: EmailSender | None) -> None:
    """Swap the sender (tests inject a fake; `None` resets)."""
    global _sender
    _sender = sender
