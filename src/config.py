"""Company list, XBRL tags and paths used by the pipeline."""
import os
from pathlib import Path

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"
SQL_DIR = ROOT / "sql"

load_dotenv(ROOT / ".env")
DATABASE_URL = os.environ.get("DATABASE_URL", "")
SEC_USER_AGENT = os.environ.get("SEC_USER_AGENT", "Muskan Garg muskangarg688@gmail.com")

# (cik, ticker, sector). Sector is a rough GICS-style label assigned by me, not an SEC field.
# Banks and insurers are left out on purpose: their statements use different line items.
COMPANIES = [
    (320193, "AAPL", "Technology"),
    (789019, "MSFT", "Technology"),
    (1045810, "NVDA", "Technology"),
    (1652044, "GOOGL", "Communication Services"),
    (1018724, "AMZN", "Consumer Discretionary"),
    (1318605, "TSLA", "Consumer Discretionary"),
    (354950, "HD", "Consumer Discretionary"),
    (80424, "PG", "Consumer Staples"),
    (21344, "KO", "Consumer Staples"),
    (104169, "WMT", "Consumer Staples"),
    (200406, "JNJ", "Health Care"),
    (34088, "XOM", "Energy"),
]

# us-gaap tags kept from the SEC "company facts" files. The mapping to metrics is in sql/02_transform.sql.
TAGS = [
    "RevenueFromContractWithCustomerExcludingAssessedTax",
    "RevenueFromContractWithCustomerIncludingAssessedTax",
    "Revenues",
    "SalesRevenueNet",
    "SalesRevenueGoodsNet",
    "GrossProfit",
    "OperatingIncomeLoss",
    "NetIncomeLoss",
    "ProfitLoss",
    "NetCashProvidedByUsedInOperatingActivities",
    "PaymentsToAcquirePropertyPlantAndEquipment",
    "PaymentsToAcquireProductiveAssets",
    "Assets",
    "Liabilities",
    "StockholdersEquity",
    "LiabilitiesAndStockholdersEquity",
    "CashAndCashEquivalentsAtCarryingValue",
]
