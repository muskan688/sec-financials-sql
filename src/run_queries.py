"""Run every query in sql/05_analysis_queries.sql and print the results.

    python -m src.run_queries
"""
import re

import psycopg

from .config import DATABASE_URL, SQL_DIR


def split_queries(text: str):
    """Split the file at lines that start with '-- Qn.' and return (title, sql) pairs."""
    parts = re.split(r"^-- (Q\d+\..*)$", text, flags=re.MULTILINE)
    return [(parts[i].strip(), parts[i + 1].strip()) for i in range(1, len(parts), 2)]


def main() -> None:
    queries = split_queries((SQL_DIR / "05_analysis_queries.sql").read_text(encoding="utf-8"))
    with psycopg.connect(DATABASE_URL) as conn:
        for title, sql in queries:
            sql = "\n".join(line for line in sql.splitlines() if not line.startswith("--"))
            cur = conn.execute(sql)
            print(f"\n=== {title}")
            print(" | ".join(col.name for col in cur.description))
            for row in cur.fetchall():
                print(" | ".join(str(v) for v in row))


if __name__ == "__main__":
    main()
