"""Tests for the XML -> DataFrame parser."""

from __future__ import annotations

from datetime import UTC, datetime

import polars as pl
import pytest
from fuelflow_ingest.parse import ROW_SCHEMA, FeedSchemaError, parse_feed

INGESTION_TS = datetime(2026, 6, 3, 10, 0, 0, tzinfo=UTC)
SOURCE_URL = "https://example.test/instantane"


def test_parse_returns_typed_dataframe_with_expected_rows(sample_xml_bytes: bytes) -> None:
    df, stats = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)

    assert stats.station_count == 4
    assert stats.parse_errors == 2  # pdv without id + prix with bad maj
    assert stats.price_row_count == 4

    assert df.height == 4
    for col, dtype in ROW_SCHEMA.items():
        assert df.schema[col] == dtype, f"column {col} expected {dtype}, got {df.schema[col]}"


def test_parse_preserves_iso8859_accents(sample_xml_bytes: bytes) -> None:
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)

    villes = set(df["ville"].drop_nulls().to_list())
    assert "SAINT-DENIS-LÈS-BOURG" in villes
    assert "Bréhan" in villes


def test_parse_divides_coords_by_100000(sample_xml_bytes: bytes) -> None:
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)

    row = df.filter(pl.col("station_id") == "1000001").row(0, named=True)
    assert row["latitude"] == pytest.approx(46.20114)
    assert row["longitude"] == pytest.approx(5.19791)


def test_parse_handles_negative_longitude(sample_xml_bytes: bytes) -> None:
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)
    row = df.filter(pl.col("station_id") == "2000002").row(0, named=True)
    assert row["longitude"] == pytest.approx(-0.567)


def test_parse_emits_decimal_euros_directly_no_div_1000(sample_xml_bytes: bytes) -> None:
    """Audit confirmed: the source ships decimal euros already.

    Raw 'valeur="1.799"' must round-trip to prix_euro == 1.799 — not 0.001799.
    """
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)
    row = df.filter((pl.col("station_id") == "1000001") & (pl.col("carburant_id") == "1")).row(
        0, named=True
    )
    assert row["prix_euro"] == pytest.approx(1.799)


def test_parse_records_maj_timestamp_naive(sample_xml_bytes: bytes) -> None:
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)
    row = df.filter((pl.col("station_id") == "1000001") & (pl.col("carburant_id") == "1")).row(
        0, named=True
    )
    assert row["maj_timestamp"] == datetime(2026, 6, 3, 9, 31, 56)


def test_parse_skips_rupture_blocks(sample_xml_bytes: bytes) -> None:
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)

    station_2_rows = df.filter(pl.col("station_id") == "2000002")
    assert station_2_rows.height == 1
    assert station_2_rows.row(0, named=True)["carburant_id"] == "5"


def test_parse_keeps_station_with_missing_coords(sample_xml_bytes: bytes) -> None:
    df, _ = parse_feed(sample_xml_bytes, INGESTION_TS, SOURCE_URL)
    station_3_rows = df.filter(pl.col("station_id") == "3000003")
    assert station_3_rows.height == 1
    row = station_3_rows.row(0, named=True)
    assert row["latitude"] is None
    assert row["longitude"] is None


def test_parse_rejects_wrong_root_tag() -> None:
    bad_xml = b'<?xml version="1.0"?><wrong_root><pdv id="1"/></wrong_root>'
    with pytest.raises(FeedSchemaError, match="unexpected root tag"):
        parse_feed(bad_xml, INGESTION_TS, SOURCE_URL)


def test_parse_rejects_zero_pdv() -> None:
    empty_xml = b'<?xml version="1.0"?><pdv_liste></pdv_liste>'
    with pytest.raises(FeedSchemaError, match="zero <pdv>"):
        parse_feed(empty_xml, INGESTION_TS, SOURCE_URL)


def test_parse_rejects_invalid_xml() -> None:
    with pytest.raises(FeedSchemaError, match="invalid XML"):
        parse_feed(b"<not-xml", INGESTION_TS, SOURCE_URL)
