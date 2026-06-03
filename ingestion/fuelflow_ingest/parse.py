"""Parse the roulez-eco XML into a typed Polars DataFrame.

The audit run (L1, see ingestion/scripts/inspect_source.py) confirmed:

- The feed is encoded in ISO-8859-1; lxml honors the XML declaration
  when fed bytes, so accents in ``<ville>`` and ``<adresse>`` survive.
- ``latitude`` and ``longitude`` are integers in the PTV_GEODECIMAL
  format and must be divided by 100000 to obtain WGS84 decimal degrees.
- ``<prix valeur="...">`` is already in **decimal euros** (e.g. ``1.957``),
  NOT in milli-euros. No ``/1000`` conversion is applied. The historical
  comment to the contrary is documented as obsolete in
  ``docs/data-model/star-schema.md``.
- Fuel id<->name mapping observed: 1 Gazole, 2 SP95, 3 E85, 4 GPLc,
  5 E10, 6 SP98.

A malformed individual ``<pdv>`` or ``<prix>`` increments a counter and
is skipped; the run does not crash. A malformed root (wrong tag or zero
``<pdv>``) is treated as schema drift and raises ``FeedSchemaError`` —
loud failure per ADR 0007.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

import polars as pl
from lxml import etree

ROW_SCHEMA = {
    "station_id": pl.Utf8,
    "cp": pl.Utf8,
    "ville": pl.Utf8,
    "adresse": pl.Utf8,
    "pop": pl.Utf8,
    "latitude": pl.Float64,
    "longitude": pl.Float64,
    "carburant_id": pl.Utf8,
    "carburant_nom": pl.Utf8,
    "maj_timestamp": pl.Datetime(time_unit="us"),
    "prix_euro": pl.Float64,
    "ingestion_ts": pl.Datetime(time_unit="us", time_zone="UTC"),
    "source_url": pl.Utf8,
}

EXPECTED_ROOT = "pdv_liste"
COORD_DIVISOR = 100_000.0
MAJ_FORMAT = "%Y-%m-%d %H:%M:%S"


class FeedSchemaError(RuntimeError):
    """Raised when the feed structure diverges from the spec — drift."""


@dataclass
class ParseStats:
    station_count: int
    price_row_count: int
    parse_errors: int


def _text(elem: etree._Element | None) -> str | None:
    if elem is None:
        return None
    text = elem.text
    if text is None:
        return None
    text = text.strip()
    return text or None


def _coord(raw: str | None) -> float | None:
    if not raw:
        return None
    try:
        return float(raw) / COORD_DIVISOR
    except (TypeError, ValueError):
        return None


def _maj(raw: str | None) -> datetime | None:
    if not raw:
        return None
    try:
        return datetime.strptime(raw, MAJ_FORMAT)
    except ValueError:
        return None


def _price_euros(raw: str | None) -> float | None:
    if not raw:
        return None
    try:
        return round(float(raw), 3)
    except (TypeError, ValueError):
        return None


def parse_feed(
    xml_bytes: bytes,
    ingestion_ts: datetime,
    source_url: str,
) -> tuple[pl.DataFrame, ParseStats]:
    try:
        root = etree.fromstring(xml_bytes)
    except etree.XMLSyntaxError as exc:
        raise FeedSchemaError(f"invalid XML payload: {exc}") from exc

    if root.tag != EXPECTED_ROOT:
        raise FeedSchemaError(f"unexpected root tag {root.tag!r}, expected {EXPECTED_ROOT!r}")

    pdvs = root.findall("pdv")
    if not pdvs:
        raise FeedSchemaError("feed contains zero <pdv> elements")

    rows: list[dict[str, object]] = []
    parse_errors = 0

    for pdv in pdvs:
        try:
            station_id = pdv.attrib.get("id")
            if not station_id:
                parse_errors += 1
                continue

            station_cols = {
                "station_id": station_id,
                "cp": pdv.attrib.get("cp") or None,
                "ville": _text(pdv.find("ville")),
                "adresse": _text(pdv.find("adresse")),
                "pop": pdv.attrib.get("pop") or None,
                "latitude": _coord(pdv.attrib.get("latitude")),
                "longitude": _coord(pdv.attrib.get("longitude")),
            }

            for prix in pdv.findall("prix"):
                try:
                    maj_ts = _maj(prix.attrib.get("maj"))
                    val = _price_euros(prix.attrib.get("valeur"))
                    cid = prix.attrib.get("id")
                    cnom = prix.attrib.get("nom")
                    if maj_ts is None or val is None or not cid or not cnom:
                        parse_errors += 1
                        continue
                    rows.append(
                        {
                            **station_cols,
                            "carburant_id": cid,
                            "carburant_nom": cnom,
                            "maj_timestamp": maj_ts,
                            "prix_euro": val,
                            "ingestion_ts": ingestion_ts,
                            "source_url": source_url,
                        }
                    )
                except (TypeError, ValueError, AttributeError):
                    parse_errors += 1
        except (TypeError, ValueError, AttributeError):
            parse_errors += 1

    df = pl.DataFrame(rows, schema=ROW_SCHEMA, orient="row")
    stats = ParseStats(
        station_count=len(pdvs),
        price_row_count=df.height,
        parse_errors=parse_errors,
    )
    return df, stats
