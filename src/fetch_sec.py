"""Download SEC EDGAR 'company facts' JSON files (public data, no API key)."""
import time

import requests

from .config import COMPANIES, RAW_DIR, SEC_USER_AGENT

URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json"


def fetch_all(refresh: bool = False) -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    for cik, ticker, _ in COMPANIES:
        path = RAW_DIR / f"CIK{cik:010d}.json"
        if path.exists() and not refresh:
            print(f"{ticker}: already downloaded")
            continue
        for attempt in range(3):
            resp = requests.get(URL.format(cik=cik), headers={"User-Agent": SEC_USER_AGENT}, timeout=60)
            if resp.status_code == 200:
                path.write_bytes(resp.content)
                print(f"{ticker}: downloaded {len(resp.content) / 1e6:.1f} MB")
                break
            print(f"{ticker}: HTTP {resp.status_code}, retrying")
            time.sleep(2 * (attempt + 1))
        else:
            raise RuntimeError(f"Could not download {ticker} (CIK {cik})")
        time.sleep(0.5)  # SEC allows at most 10 requests per second
