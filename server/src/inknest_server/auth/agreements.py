CURRENT_PRIVACY_POLICY_VERSION = "2026-08-31.1"
CURRENT_TERMS_VERSION = "2026-08-31.1"


def agreements_are_current(
    *, privacy_policy_version: str | None, terms_version: str | None
) -> bool:
    return (
        privacy_policy_version == CURRENT_PRIVACY_POLICY_VERSION
        and terms_version == CURRENT_TERMS_VERSION
    )
