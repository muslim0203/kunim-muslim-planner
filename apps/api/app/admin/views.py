"""Read-only SQLAdmin views."""

from __future__ import annotations

from sqladmin import ModelView

from app.modules.users.models import User


class UserAdmin(ModelView, model=User):
    name = "User"
    name_plural = "Users"
    icon = "fa-solid fa-user"

    column_list = [
        User.id,
        User.email,
        User.role,
        User.is_active,
        User.locale,
        User.created_at,
        User.deleted_at,
    ]
    column_searchable_list = [User.email]
    column_sortable_list = [User.email, User.created_at]

    can_create = False
    can_edit = False
    can_delete = False
    can_export = False
