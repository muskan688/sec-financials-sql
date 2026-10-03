"""Parse the downloaded JSON files and load them into raw.facts and core.dim_company."""
import json

import psycopg

from .config import COMPANIES, DATABASE_URL, RAW_DIR, TAGS

RAW_COLUMNS = "cik, tag, unit, start_date, end_date, val, accn, fy, fp, form, filed, frame"


def parse_companyfacts(cik: int, data: dict, tags=TAGS):
    """Yield one tuple per reported fact for the chosen us-gaap tags."""
    gaap = data.get("facts", {}).get("us-gaap", {})
    for tag in tags:
        for unit, entries in gaap.get(tag, {}).get("units", {}).items():
            for e in entries:
                yield (
                    cik, tag, unit, e.get("start"), e["end"], e["val"], e.get("accn"),
                    e.get("fy"), e.get("fp"), e.get("form"), e.get("filed"), e.get("frame"),
                )


def load_raw() -> None:
    with psycopg.connect(DATABASE_URL) as conn:
        with conn.cursor() as cur:
            cur.execute("truncate raw.facts")
            for cik, ticker, sector in COMPANIES:
                path = RAW_DIR / f"CIK{cik:010d}.json"
                data = json.loads(path.read_text(encoding="utf-8"))
                cur.execute(
                    """insert into core.dim_company (cik, ticker, name, sector) values (%s, %s, %s, %s)
                       on conflict (cik) do update set ticker = excluded.ticker,
                       name = excluded.name, sector = excluded.sector""",
                    (cik, ticker, data["entityName"], sector),
                )
                with cur.copy(f"copy raw.facts ({RAW_COLUMNS}) from stdin") as cp:
                    n = 0
                    for row in parse_companyfacts(cik, data):
                        cp.write_row(row)
                        n += 1
                print(f"{ticker}: {n} facts loaded")
