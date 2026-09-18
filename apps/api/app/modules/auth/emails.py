"""The password-reset message, in the language the account is set to.

Plain text, short, and it says two things a reset mail has to say: the code
with how long it lasts, and what to do if the reader did not ask for it.
"""

from __future__ import annotations

from app.integrations.email import EmailMessage

_SUBJECT = {
    "uz": "KUNIM: parolni tiklash kodi",
    "uz_Cyrl": "KUNIM: паролни тиклаш коди",
    "ru": "KUNIM: код для сброса пароля",
    "en": "KUNIM: your password reset code",
}

_BODY = {
    "uz": (
        "Assalomu alaykum!\n\n"
        "Parolni tiklash kodingiz: {code}\n"
        "Kod {minutes} daqiqa davomida amal qiladi.\n\n"
        "Agar parolni tiklashni siz so‘ramagan bo‘lsangiz, bu xatga e’tibor bermang: "
        "parolingiz o‘zgarmaydi.\n"
    ),
    "uz_Cyrl": (
        "Ассалому алайкум!\n\n"
        "Паролни тиклаш кодингиз: {code}\n"
        "Код {minutes} дақиқа давомида амал қилади.\n\n"
        "Агар паролни тиклашни сиз сўрамаган бўлсангиз, бу хатга эътибор берманг: "
        "паролингиз ўзгармайди.\n"
    ),
    "ru": (
        "Здравствуйте!\n\n"
        "Ваш код для сброса пароля: {code}\n"
        "Код действует {minutes} минут.\n\n"
        "Если сброс пароля запрашивали не вы, просто не отвечайте на это письмо: "
        "пароль останется прежним.\n"
    ),
    "en": (
        "Hello,\n\n"
        "Your password reset code is: {code}\n"
        "It works for the next {minutes} minutes.\n\n"
        "If you did not ask to reset your password, ignore this email: "
        "your password stays as it is.\n"
    ),
}


def password_reset_email(*, to: str, code: str, minutes: int, locale: str) -> EmailMessage:
    """The reset mail, falling back to English for an unknown locale."""
    language = locale if locale in _SUBJECT else "en"
    return EmailMessage(
        to=to,
        subject=_SUBJECT[language],
        body=_BODY[language].format(code=code, minutes=minutes),
    )
