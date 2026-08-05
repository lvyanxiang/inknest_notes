import hashlib
import json
from collections.abc import Mapping
from typing import cast


class CanonicalJsonError(ValueError):
    pass


def canonicalize_json_object(content: Mapping[str, object]) -> bytes:
    """Serialize one JSON object deterministically for hashing and storage."""

    try:
        canonical = json.dumps(
            dict(content),
            ensure_ascii=False,
            allow_nan=False,
            sort_keys=True,
            separators=(",", ":"),
        )
    except (TypeError, ValueError) as error:
        raise CanonicalJsonError("content must be a finite JSON object") from error
    return canonical.encode("utf-8")


def normalized_json_object(content: Mapping[str, object]) -> dict[str, object]:
    canonical = canonicalize_json_object(content)
    return cast(dict[str, object], json.loads(canonical))


def content_hash(content: Mapping[str, object]) -> str:
    return hashlib.sha256(canonicalize_json_object(content)).hexdigest()
