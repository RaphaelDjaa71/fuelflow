"""Tests for the HTTP download + ZIP extraction layer."""

from __future__ import annotations

import io
import zipfile

import httpx
import pytest
from fuelflow_ingest.download import (
    FeedPayload,
    TransientHTTPError,
    _extract_xml,
    _http_get,
    download_feed,
)
from pytest_httpx import HTTPXMock

URL = "https://example.test/instantane"


def _make_zip(xml_payload: bytes, name: str = "PrixCarburants_instantane.xml") -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(name, xml_payload)
    return buf.getvalue()


def test_extract_xml_picks_first_xml_entry() -> None:
    xml = b'<?xml version="1.0"?><root/>'
    zip_bytes = _make_zip(xml, name="random_name_abc.xml")
    out, entry = _extract_xml(zip_bytes)
    assert out == xml
    assert entry == "random_name_abc.xml"


def test_extract_xml_raises_when_no_xml_inside() -> None:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, mode="w") as zf:
        zf.writestr("readme.txt", b"not xml")
    with pytest.raises(ValueError, match="no .xml entry"):
        _extract_xml(buf.getvalue())


def test_download_feed_retries_after_transient_503(
    httpx_mock: HTTPXMock,
) -> None:
    _http_get.retry.statistics.clear()

    xml = b'<?xml version="1.0"?><pdv_liste/>'
    zip_bytes = _make_zip(xml)

    httpx_mock.add_response(url=URL, status_code=503)
    httpx_mock.add_response(url=URL, status_code=503)
    httpx_mock.add_response(url=URL, status_code=200, content=zip_bytes)

    payload = download_feed(URL, timeout=5.0, max_attempts=5)

    assert isinstance(payload, FeedPayload)
    assert payload.xml_bytes == xml
    assert payload.zip_bytes == zip_bytes
    assert len(httpx_mock.get_requests()) == 3


def test_download_feed_raises_after_max_attempts_on_persistent_503(
    httpx_mock: HTTPXMock,
) -> None:
    _http_get.retry.statistics.clear()

    for _ in range(3):
        httpx_mock.add_response(url=URL, status_code=503)

    with pytest.raises(TransientHTTPError):
        download_feed(URL, timeout=5.0, max_attempts=3)


def test_download_feed_propagates_non_retryable_4xx(httpx_mock: HTTPXMock) -> None:
    httpx_mock.add_response(url=URL, status_code=404, content=b"")

    with pytest.raises(httpx.HTTPStatusError):
        download_feed(URL, timeout=5.0, max_attempts=5)
