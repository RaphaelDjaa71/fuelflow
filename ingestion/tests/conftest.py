"""Pytest fixtures.

The sample XML on disk is generated from a Python literal at session
start so that the ISO-8859-1 encoding stays correct independent of
whatever encoding the file is checked out as.
"""

from __future__ import annotations

from pathlib import Path

import pytest

FIXTURES_DIR = Path(__file__).parent / "fixtures"
SAMPLE_XML_PATH = FIXTURES_DIR / "instantane_sample.xml"

SAMPLE_XML_UNICODE = """\
<?xml version="1.0" encoding="ISO-8859-1" standalone="yes"?>
<pdv_liste>
  <pdv id="1000001" latitude="4620114" longitude="519791" cp="01000" pop="R">
    <adresse>ROUTE NATIONALE</adresse>
    <ville>SAINT-DENIS-LÈS-BOURG</ville>
    <horaires/>
    <services><service>Automate CB</service></services>
    <prix nom="Gazole" id="1" maj="2026-06-03 09:31:56" valeur="1.799" />
    <prix nom="SP95" id="2" maj="2026-06-03 09:31:56" valeur="1.889" />
  </pdv>
  <pdv id="2000002" latitude="4377300" longitude="-56700" cp="40500" pop="A">
    <adresse>AIRE DE REPOS</adresse>
    <ville>Bréhan</ville>
    <horaires/>
    <prix nom="E10" id="5" maj="2026-06-02 18:00:00" valeur="1.911" />
    <rupture nom="Gazole" id="1" debut="2026-06-01" fin=""/>
  </pdv>
  <pdv id="3000003" latitude="" longitude="" pop="R">
    <adresse></adresse>
    <ville></ville>
    <horaires/>
    <prix nom="E85" id="3" maj="bad-timestamp" valeur="0.798" />
    <prix nom="SP98" id="6" maj="2026-06-03 10:00:00" valeur="2.024" />
  </pdv>
  <pdv latitude="0" longitude="0" cp="" pop="R">
    <ville>STATION WITHOUT ID</ville>
    <prix nom="Gazole" id="1" maj="2026-06-03 10:00:00" valeur="1.999" />
  </pdv>
</pdv_liste>
"""


@pytest.fixture(scope="session", autouse=True)
def _materialize_sample_xml() -> None:
    FIXTURES_DIR.mkdir(parents=True, exist_ok=True)
    SAMPLE_XML_PATH.write_bytes(SAMPLE_XML_UNICODE.encode("latin-1"))


@pytest.fixture()
def sample_xml_bytes() -> bytes:
    return SAMPLE_XML_PATH.read_bytes()
