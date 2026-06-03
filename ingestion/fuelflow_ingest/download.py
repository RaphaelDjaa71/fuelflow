"""Download the live XML-ZIP feed with retry.

Returns both the raw ZIP bytes (kept for the rejoin-from-source promise
in ADR 0005) and the inner XML bytes (passed to the parser). The XML
entry name in the ZIP is not assumed to be stable; we pick the first
``*.xml`` entry.
"""

from __future__ import annotations

import io
import zipfile
from dataclasses import dataclass

import httpx
from tenacity import (
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential_jitter,
)

_RETRYABLE_STATUS = frozenset({429, 500, 502, 503, 504})


class TransientHTTPError(Exception):
    """HTTP response that is safe to retry (5xx, 429)."""


@dataclass(frozen=True)
class FeedPayload:
    """A successfully downloaded feed: the raw ZIP and the inner XML."""

    zip_bytes: bytes
    xml_bytes: bytes
    xml_entry_name: str


def _is_retryable(exc: BaseException) -> bool:
    return isinstance(exc, httpx.TransportError | TransientHTTPError)


@retry(
    reraise=True,
    stop=stop_after_attempt(5),
    wait=wait_exponential_jitter(initial=1, max=30, jitter=2),
    retry=retry_if_exception_type((httpx.TransportError, TransientHTTPError)),
)
def _http_get(url: str, timeout: float) -> bytes:
    with httpx.Client(timeout=timeout, follow_redirects=True) as client:
        response = client.get(url)
    if response.status_code in _RETRYABLE_STATUS:
        raise TransientHTTPError(f"retryable HTTP {response.status_code} from {url}")
    response.raise_for_status()
    return response.content


def _extract_xml(zip_bytes: bytes) -> tuple[bytes, str]:
    with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
        xml_entries = [n for n in zf.namelist() if n.lower().endswith(".xml")]
        if not xml_entries:
            raise ValueError(f"no .xml entry in archive (entries: {zf.namelist()})")
        entry = xml_entries[0]
        return zf.read(entry), entry


def download_feed(
    url: str,
    timeout: float = 60.0,
    max_attempts: int = 5,
) -> FeedPayload:
    _http_get.retry.stop = stop_after_attempt(max_attempts)
    zip_bytes = _http_get(url, timeout=timeout)
    xml_bytes, entry = _extract_xml(zip_bytes)
    return FeedPayload(zip_bytes=zip_bytes, xml_bytes=xml_bytes, xml_entry_name=entry)
