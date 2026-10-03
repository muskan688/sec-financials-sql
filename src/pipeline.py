"""Run the whole pipeline: download, load raw data, transform, build views, run checks.

    python -m src.pipeline            # use files already in data/raw
    python -m src.pipeline --refresh  # download again
"""
import argparse

import psycopg

from .config import DATABASE_URL, SQL_DIR
from .fetch_sec import fetch_all
from .load_raw import load_raw

SQL_FILES = ["01_schema.sql"]
SQL_AFTER_LOAD = ["02_transform.sql", "03_kpis.sql", "04_checks.sql"]


def run_sql(names) -> None:
    with psycopg.connect(DATABASE_URL, autocommit=True) as conn:
        for name in names:
            conn.execute((SQL_DIR / name).read_text(encoding="utf-8"))
            print(f"ran {name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--refresh", action="store_true", help="download the SEC files again")
    args = parser.parse_args()
    if not DATABASE_URL:
        raise SystemExit("DATABASE_URL is not set. Copy .env.example to .env and fill it in.")

    fetch_all(refresh=args.refresh)
    run_sql(SQL_FILES)
    load_raw()
    run_sql(SQL_AFTER_LOAD)


if __name__ == "__main__":
    main()
