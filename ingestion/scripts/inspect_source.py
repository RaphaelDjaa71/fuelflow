"""Throwaway schema audit script. Not part of the package.

Downloads the live roulez-eco snapshot, unzips, and prints enough of the
raw structure to confirm parser assumptions before any production code is
written:

- declared XML encoding
- root tag and pdv count
- attributes of a sample pdv (cp, latitude, longitude, pop)
- a few raw <prix> blocks
- distinct (prix@id, prix@nom) mapping observed in the feed
- sample of raw <prix valeur=...> for Gazole, to confirm the unit
  (millieuros vs euros)

Run from repo root:
    uv run python ingestion/scripts/inspect_source.py
"""

from __future__ import annotations

import io
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter

URL = "https://donnees.roulez-eco.fr/opendata/instantane"
TIMEOUT_S = 60


def main() -> None:
    print(f"GET {URL}")
    with urllib.request.urlopen(URL, timeout=TIMEOUT_S) as resp:
        zip_bytes = resp.read()
    print(f"  bytes downloaded: {len(zip_bytes):,}")

    zf = zipfile.ZipFile(io.BytesIO(zip_bytes))
    xml_entries = [n for n in zf.namelist() if n.lower().endswith(".xml")]
    print(f"  zip entries: {zf.namelist()}")
    print(f"  xml entries: {xml_entries}")
    if not xml_entries:
        sys.exit("No XML inside the ZIP")

    xml_bytes = zf.read(xml_entries[0])
    print(f"  xml bytes : {len(xml_bytes):,}")
    print(f"  first 200 bytes (raw): {xml_bytes[:200]!r}")

    # XML declaration
    first_line = xml_bytes.split(b"\n", 1)[0]
    print(f"  XML declaration: {first_line!r}")

    root = ET.fromstring(xml_bytes)
    print(f"  root tag: {root.tag}")
    pdvs = root.findall("pdv")
    print(f"  pdv count: {len(pdvs):,}")

    if not pdvs:
        sys.exit("No <pdv> found")

    sample = pdvs[0]
    print("\n--- sample pdv [0] ---")
    print(f"  attribs: {dict(sample.attrib)}")
    print(f"  child tags: {[c.tag for c in sample]}")

    # Raw <prix> blocks
    print("\n--- first 5 raw <prix> blocks (across feed) ---")
    n = 0
    for pdv in pdvs:
        for prix in pdv.findall("prix"):
            print(f"  {ET.tostring(prix, encoding='unicode').strip()}")
            n += 1
            if n >= 5:
                break
        if n >= 5:
            break

    # Distinct (prix@id, prix@nom) mapping
    print("\n--- distinct (prix@id, prix@nom) observed ---")
    pairs: Counter[tuple[str, str]] = Counter()
    for pdv in pdvs:
        for prix in pdv.findall("prix"):
            pairs[(prix.attrib.get("id", "?"), prix.attrib.get("nom", "?"))] += 1

    def _sort_key(kv: tuple[tuple[str, str], int]) -> int:
        pid_str = kv[0][0]
        return int(pid_str) if pid_str.isdigit() else 999

    for (pid, pnom), c in sorted(pairs.items(), key=_sort_key):
        print(f"  id={pid!r:>4}  nom={pnom!r:<10}  count={c:,}")

    # Sample raw `valeur` for Gazole to confirm the unit
    print("\n--- sample raw <prix valeur=...> for nom=Gazole (first 8) ---")
    seen = 0
    for pdv in pdvs:
        for prix in pdv.findall("prix"):
            if prix.attrib.get("nom") == "Gazole":
                v = prix.attrib.get("valeur")
                print(f"  raw valeur={v!r}  pdv@id={pdv.attrib.get('id')}")
                seen += 1
                if seen >= 8:
                    break
        if seen >= 8:
            break

    # Coord sample (raw vs /100000)
    print("\n--- coord sample (raw vs /100000) on first 5 pdvs ---")
    for pdv in pdvs[:5]:
        rlat = pdv.attrib.get("latitude")
        rlon = pdv.attrib.get("longitude")
        try:
            lat = float(rlat) / 100000 if rlat else None
            lon = float(rlon) / 100000 if rlon else None
        except ValueError:
            lat = lon = None
        print(f"  raw_lat={rlat!r:>10}  raw_lon={rlon!r:>10}  -> lat={lat}  lon={lon}")

    # cp / ville presence
    print("\n--- field presence on first 50 pdvs ---")
    n50 = pdvs[:50]
    cp_missing = sum(1 for p in n50 if not p.attrib.get("cp"))
    ville_missing = 0
    for p in n50:
        v = p.find("ville")
        if v is None or not (v.text or "").strip():
            ville_missing += 1
    print(f"  cp missing/empty: {cp_missing}/50")
    print(f"  <ville> missing/empty: {ville_missing}/50")

    # Sample accented ville to confirm encoding handling later
    print("\n--- first 5 accented-looking villes ---")
    accented_chars = "àâäçéèêëîïôöùûüÿñæœÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸÑÆŒ"
    accented = []
    for p in pdvs:
        v = p.find("ville")
        if v is not None and v.text and any(c in v.text for c in accented_chars):
            accented.append(v.text)
            if len(accented) >= 5:
                break
    for t in accented:
        print(f"  {t!r}")


if __name__ == "__main__":
    main()
