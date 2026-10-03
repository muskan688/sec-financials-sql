from src.load_raw import parse_companyfacts
from src.run_queries import split_queries

SAMPLE = {
    "entityName": "TEST CORP",
    "facts": {
        "us-gaap": {
            "Revenues": {
                "units": {
                    "USD": [
                        {"start": "2022-01-01", "end": "2022-12-31", "val": 100, "accn": "a-1",
                         "fy": 2022, "fp": "FY", "form": "10-K", "filed": "2023-02-01"},
                    ]
                }
            },
            "Assets": {
                "units": {"USD": [{"end": "2022-12-31", "val": 500, "accn": "a-1", "fy": 2022,
                                   "fp": "FY", "form": "10-K", "filed": "2023-02-01"}]}
            },
            "SomeOtherTag": {"units": {"USD": [{"end": "2022-12-31", "val": 1}]}},
        }
    },
}


def test_parse_keeps_only_chosen_tags():
    rows = list(parse_companyfacts(1, SAMPLE, tags=["Revenues", "Assets"]))
    assert len(rows) == 2
    assert {r[1] for r in rows} == {"Revenues", "Assets"}


def test_parse_balance_sheet_item_has_no_start_date():
    rows = {r[1]: r for r in parse_companyfacts(1, SAMPLE, tags=["Revenues", "Assets"])}
    assert rows["Assets"][3] is None
    assert rows["Revenues"][3] == "2022-01-01"


def test_parse_ignores_missing_tag():
    assert list(parse_companyfacts(1, SAMPLE, tags=["NotInFile"])) == []


def test_split_queries_finds_each_block():
    text = "-- Q1. First?\nselect 1;\n\n-- Q2. Second?\nselect 2;\n"
    assert split_queries(text) == [("Q1. First?", "select 1;"), ("Q2. Second?", "select 2;")]
