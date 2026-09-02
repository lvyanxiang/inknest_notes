from dataclasses import dataclass
from datetime import UTC, datetime
from uuid import UUID, uuid4

from sqlalchemy import Select, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from inknest_server.auth.agreements import (
    CURRENT_PRIVACY_POLICY_VERSION,
    CURRENT_TERMS_VERSION,
    agreements_are_current,
)
from inknest_server.auth.passwords import PasswordManager
from inknest_server.auth.rate_limit import (
    LoginAttempt,
    LoginRateLimiter,
    LoginRateLimitExceededError,
)
from inknest_server.auth.tokens import TokenManager
from inknest_server.errors import ApiError
from inknest_server.models import AccountDeletionRequest, Device, RefreshToken, User
from inknest_server.storage import ObjectStorage


@dataclass(frozen=True)
class AuthResult:
    access_token: str
    refresh_token: str
    user: User
    device: Device


class AuthService:
    def __init__(
        self,
        session: AsyncSession,
        password_manager: PasswordManager,
        token_manager: TokenManager,
        login_rate_limiter: LoginRateLimiter,
        object_storage: ObjectStorage,
    ) -> None:
        self._session = session
        self._passwords = password_manager
        self._tokens = token_manager
        self._login_rate_limiter = login_rate_limiter
        self._storage = object_storage

    @property
    def access_token_seconds(self) -> int:
        return self._tokens.access_token_seconds

    async def register(
        self,
        *,
        email: str,
        password: str,
        device_name: str,
        platform: str,
        client_instance_id: str | None,
        privacy_policy_version: str,
        terms_version: str,
    ) -> AuthResult:
        self._require_current_agreements(
            privacy_policy_version=privacy_policy_version,
            terms_version=terms_version,
        )
        normalized_email = email.strip().lower()
        if await self._find_user_by_email(normalized_email) is not None:
            raise ApiError(
                code="email_already_registered",
                message="An account already exists for this email address.",
                status_code=409,
            )

        user = User(
            email=normalized_email,
            password_hash=await self._passwords.hash(password),
            privacy_policy_version=privacy_policy_version,
            terms_version=terms_version,
            agreements_accepted_at=datetime.now(UTC),
        )
        device = Device(
            user=user,
            name=device_name.strip(),
            platform=platform.strip().lower(),
            client_instance_id=client_instance_id,
        )
        self._session.add_all([user, device])
        await self._session.flush()
        result = self._issue_session(user=user, device=device, family_id=uuid4())
        try:
            await self._session.commit()
        except IntegrityError as error:
            await self._session.rollback()
            raise ApiError(
                code="email_already_registered",
                message="An account already exists for this email address.",
                status_code=409,
            ) from error
        return result

    async def login(
        self,
        *,
        email: str,
        password: str,
        device_name: str,
        platform: str,
        client_instance_id: str | None,
        client_id: str,
    ) -> AuthResult:
        normalized_email = email.strip().lower()
        attempt = await self._acquire_login_attempt(
            email=normalized_email,
            client_id=client_id,
        )
        try:
            user = await self._find_user_by_email(normalized_email)
            password_hash = user.password_hash if user is not None else None
            password_is_valid = await self._passwords.verify(password_hash, password)
        except Exception:
            await self._login_rate_limiter.cancel(attempt)
            raise

        if not password_is_valid or user is None or not user.is_active:
            raise self._invalid_credentials()
        await self._login_rate_limiter.mark_succeeded(attempt)

        device = await self._find_device_by_client_instance_id(
            user_id=user.id,
            client_instance_id=client_instance_id,
        )
        if device is None:
            try:
                async with self._session.begin_nested():
                    device = Device(
                        user_id=user.id,
                        name=device_name.strip(),
                        platform=platform.strip().lower(),
                        client_instance_id=client_instance_id,
                    )
                    self._session.add(device)
                    await self._session.flush()
            except IntegrityError:
                device = await self._find_device_by_client_instance_id(
                    user_id=user.id,
                    client_instance_id=client_instance_id,
                )
                if device is None:
                    raise
        else:
            device.name = device_name.strip()
            device.platform = platform.strip().lower()
            device.last_seen_at = datetime.now(UTC)
            device.revoked_at = None
        result = self._issue_session(user=user, device=device, family_id=uuid4())
        await self._session.commit()
        return result

    async def _find_device_by_client_instance_id(
        self,
        *,
        user_id: UUID,
        client_instance_id: str | None,
    ) -> Device | None:
        if client_instance_id is None:
            return None
        device: Device | None = await self._session.scalar(
            select(Device).where(
                Device.user_id == user_id,
                Device.client_instance_id == client_instance_id,
            )
        )
        return device

    async def _acquire_login_attempt(
        self,
        *,
        email: str,
        client_id: str,
    ) -> LoginAttempt:
        try:
            return await self._login_rate_limiter.acquire(
                email=email,
                client_id=client_id,
            )
        except LoginRateLimitExceededError as error:
            retry_after = error.retry_after_seconds
            raise ApiError(
                code="login_rate_limited",
                message="Too many login attempts. Try again later.",
                status_code=429,
                details={"retryAfterSeconds": retry_after},
                headers={"Retry-After": str(retry_after)},
            ) from error

    async def refresh(self, raw_token: str) -> AuthResult:
        token_hash = self._tokens.hash_refresh_token(raw_token)
        stored_token = await self._session.scalar(
            select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        )
        if stored_token is None:
            raise self._invalid_refresh_token()

        now = datetime.now(UTC)
        if stored_token.revoked_at is not None:
            await self._revoke_family(stored_token.family_id, now)
            await self._session.commit()
            raise ApiError(
                code="refresh_token_reused",
                message="This refresh token has already been used.",
                status_code=401,
            )
        if self._as_utc(stored_token.expires_at) <= now:
            stored_token.revoked_at = now
            await self._session.commit()
            raise self._invalid_refresh_token()

        user = await self._session.get(User, stored_token.user_id)
        device = await self._session.get(Device, stored_token.device_id)
        if (
            user is None
            or not user.is_active
            or device is None
            or device.revoked_at is not None
        ):
            stored_token.revoked_at = now
            await self._session.commit()
            raise self._invalid_refresh_token()

        stored_token.revoked_at = now
        device.last_seen_at = now
        result = self._issue_session(
            user=user,
            device=device,
            family_id=stored_token.family_id,
        )
        replacement = await self._session.scalar(
            select(RefreshToken).where(
                RefreshToken.token_hash
                == self._tokens.hash_refresh_token(result.refresh_token)
            )
        )
        if replacement is None:
            raise RuntimeError("refresh token replacement was not created")
        stored_token.replaced_by_token_id = replacement.id
        await self._session.commit()
        return result

    async def logout(self, raw_token: str) -> None:
        token_hash = self._tokens.hash_refresh_token(raw_token)
        stored_token = await self._session.scalar(
            select(RefreshToken).where(RefreshToken.token_hash == token_hash)
        )
        if stored_token is not None and stored_token.revoked_at is None:
            stored_token.revoked_at = datetime.now(UTC)
            await self._session.commit()

    async def list_devices(self, user_id: UUID) -> list[Device]:
        result = await self._session.scalars(
            select(Device)
            .where(Device.user_id == user_id)
            .order_by(Device.created_at.desc())
        )
        return list(result)

    async def revoke_device(self, *, user_id: UUID, device_id: UUID) -> None:
        device = await self._session.scalar(
            select(Device).where(
                Device.id == device_id,
                Device.user_id == user_id,
            )
        )
        if device is None:
            raise ApiError(
                code="device_not_found",
                message="The device was not found.",
                status_code=404,
            )

        now = datetime.now(UTC)
        if device.revoked_at is None:
            device.revoked_at = now
            await self._session.execute(
                update(RefreshToken)
                .where(
                    RefreshToken.device_id == device.id,
                    RefreshToken.revoked_at.is_(None),
                )
                .values(revoked_at=now)
            )
            await self._session.commit()

    async def accept_agreements(
        self,
        *,
        user: User,
        privacy_policy_version: str,
        terms_version: str,
    ) -> None:
        self._require_current_agreements(
            privacy_policy_version=privacy_policy_version,
            terms_version=terms_version,
        )
        user.privacy_policy_version = privacy_policy_version
        user.terms_version = terms_version
        user.agreements_accepted_at = datetime.now(UTC)
        await self._session.commit()

    async def change_password(
        self,
        *,
        user: User,
        current_device_id: UUID,
        current_password: str,
        new_password: str,
    ) -> None:
        if not await self._passwords.verify(user.password_hash, current_password):
            raise self._invalid_current_password()
        if await self._passwords.verify(user.password_hash, new_password):
            raise ApiError(
                code="password_unchanged",
                message="The new password must be different.",
                status_code=400,
            )
        now = datetime.now(UTC)
        user.password_hash = await self._passwords.hash(new_password)
        other_device_ids = select(Device.id).where(
            Device.user_id == user.id,
            Device.id != current_device_id,
        )
        await self._session.execute(
            update(Device)
            .where(Device.id.in_(other_device_ids), Device.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await self._session.execute(
            update(RefreshToken)
            .where(
                RefreshToken.user_id == user.id,
                RefreshToken.device_id != current_device_id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=now)
        )
        await self._session.commit()

    async def request_account_deletion(
        self,
        *,
        user: User,
        password: str,
    ) -> AccountDeletionRequest:
        if not await self._passwords.verify(user.password_hash, password):
            raise self._invalid_current_password()
        existing = await self._session.scalar(
            select(AccountDeletionRequest).where(
                AccountDeletionRequest.user_id == user.id
            )
        )
        if existing is not None:
            return await self._complete_account_deletion(existing)

        try:
            object_keys = await self._storage.list_object_keys(f"users/{user.id}/")
        except Exception as error:
            raise ApiError(
                code="account_deletion_unavailable",
                message="Account deletion could not start. Try again later.",
                status_code=503,
            ) from error

        now = datetime.now(UTC)
        user.is_active = False
        await self._session.execute(
            update(Device)
            .where(Device.user_id == user.id, Device.revoked_at.is_(None))
            .values(revoked_at=now)
        )
        await self._session.execute(
            update(RefreshToken)
            .where(
                RefreshToken.user_id == user.id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=now)
        )
        request = AccountDeletionRequest(user_id=user.id, object_keys=object_keys)
        self._session.add(request)
        await self._session.commit()
        return await self._complete_account_deletion(request)

    async def retry_pending_account_deletions(self) -> tuple[int, int]:
        requests = list(
            await self._session.scalars(
                select(AccountDeletionRequest).where(
                    AccountDeletionRequest.status == "pending"
                )
            )
        )
        completed = 0
        for request in requests:
            result = await self._complete_account_deletion(request)
            if result.status == "completed":
                completed += 1
        return (completed, len(requests) - completed)

    async def _complete_account_deletion(
        self, request: AccountDeletionRequest
    ) -> AccountDeletionRequest:
        try:
            current_keys = await self._storage.list_object_keys(
                f"users/{request.user_id}/"
            )
        except Exception as error:
            request.attempts += 1
            request.last_error = type(error).__name__
            await self._session.commit()
            return request

        remaining: list[str] = []
        last_error: str | None = None
        candidates = sorted(set(request.object_keys).union(current_keys))
        for object_key in candidates:
            try:
                await self._storage.delete_object(object_key)
            except Exception as error:
                remaining.append(object_key)
                last_error = type(error).__name__
        request.attempts += 1
        request.object_keys = remaining
        request.last_error = last_error
        if remaining:
            await self._session.commit()
            return request

        try:
            remaining = await self._storage.list_object_keys(
                f"users/{request.user_id}/"
            )
        except Exception as error:
            request.last_error = type(error).__name__
            await self._session.commit()
            return request
        if remaining:
            request.object_keys = remaining
            request.last_error = "objects_created_during_deletion"
            await self._session.commit()
            return request

        user = await self._session.get(User, request.user_id)
        if user is not None:
            await self._session.delete(user)
        request.status = "completed"
        request.completed_at = datetime.now(UTC)
        await self._session.commit()
        return request

    async def _find_user_by_email(self, email: str) -> User | None:
        statement: Select[tuple[User]] = select(User).where(User.email == email)
        result = await self._session.execute(statement)
        return result.scalar_one_or_none()

    def _issue_session(
        self,
        *,
        user: User,
        device: Device,
        family_id: UUID,
    ) -> AuthResult:
        raw_token, token_hash, expires_at = self._tokens.create_refresh_token()
        refresh_token = RefreshToken(
            user_id=user.id,
            device_id=device.id,
            family_id=family_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
        self._session.add(refresh_token)
        return AuthResult(
            access_token=self._tokens.create_access_token(
                user_id=user.id,
                device_id=device.id,
            ),
            refresh_token=raw_token,
            user=user,
            device=device,
        )

    async def _revoke_family(self, family_id: UUID, revoked_at: datetime) -> None:
        await self._session.execute(
            update(RefreshToken)
            .where(
                RefreshToken.family_id == family_id,
                RefreshToken.revoked_at.is_(None),
            )
            .values(revoked_at=revoked_at)
        )

    @staticmethod
    def _as_utc(value: datetime) -> datetime:
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value

    @staticmethod
    def _invalid_credentials() -> ApiError:
        return ApiError(
            code="invalid_credentials",
            message="The email or password is incorrect.",
            status_code=401,
        )

    @staticmethod
    def _invalid_current_password() -> ApiError:
        return ApiError(
            code="current_password_invalid",
            message="The current password is incorrect.",
            status_code=401,
        )

    @staticmethod
    def _invalid_refresh_token() -> ApiError:
        return ApiError(
            code="invalid_refresh_token",
            message="The refresh token is invalid or expired.",
            status_code=401,
        )

    @staticmethod
    def _require_current_agreements(
        *, privacy_policy_version: str, terms_version: str
    ) -> None:
        if agreements_are_current(
            privacy_policy_version=privacy_policy_version,
            terms_version=terms_version,
        ):
            return
        raise ApiError(
            code="agreement_version_outdated",
            message="Review and accept the current Privacy Policy and Terms.",
            status_code=409,
            details={
                "privacyPolicyVersion": CURRENT_PRIVACY_POLICY_VERSION,
                "termsVersion": CURRENT_TERMS_VERSION,
            },
        )
