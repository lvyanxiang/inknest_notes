import re
import unicodedata
from urllib.parse import quote

_KIND_DIRECTORIES = {
    "pdf": "pdfs",
    "image": "images",
    "audio": "audio",
}
_UNSAFE_FILENAME = re.compile(r"[^\w.\-]+", flags=re.UNICODE)


def build_asset_object_key(
    *,
    user_id: str,
    notebook_id: str,
    asset_id: str,
    kind: str,
    original_filename: str,
) -> str:
    directory = _KIND_DIRECTORIES[kind]
    safe_notebook_id = quote(notebook_id, safe="-_.~")
    safe_asset_id = quote(asset_id, safe="-_.~")
    safe_filename = sanitize_filename(original_filename)
    return (
        f"users/{user_id}/notebooks/{safe_notebook_id}/"
        f"{directory}/{safe_asset_id}/{safe_filename}"
    )


def sanitize_filename(filename: str) -> str:
    normalized = unicodedata.normalize("NFKC", filename).replace("\\", "/")
    basename = normalized.rsplit("/", maxsplit=1)[-1].strip()
    safe = _UNSAFE_FILENAME.sub("_", basename).strip("._")
    if not safe:
        safe = "upload.bin"
    return safe[:160]
