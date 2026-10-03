-- Data quality checks. Each run appends rows to dq.check_results.
-- View the latest run with: select * from dq.latest_checks;

insert into dq.reviewed_exceptions (check_name, ticker, fiscal_year, reason) values
    ('revenue_change_is_plausible', 'TSLA', 2013,
     'Real change, checked in the 10-K filings: revenue was 413 million USD in 2012 and 2,013 million USD in 2013.')
on conflict do nothing;

-- 1. Balance sheet: total assets must equal total liabilities and equity.
with bad as (
    select c.ticker, a.fiscal_year
    from core.fact_annual a
    join core.fact_annual l on l.cik = a.cik and l.period_end = a.period_end
                           and l.metric_code = 'liabilities_and_equity'
    join core.dim_company c on c.cik = a.cik
    where a.metric_code = 'total_assets' and abs(a.value - l.value) > 0.001 * a.value
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'assets_equal_liabilities_and_equity', 'error',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' ' || fiscal_year, ', ' order by ticker, fiscal_year), 'no violations')
from bad;

-- 2. Gross profit cannot be larger than revenue.
with bad as (
    select ticker, fiscal_year from mart.annual_wide where gross_profit > revenue
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'gross_profit_not_above_revenue', 'error',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' ' || fiscal_year, ', ' order by ticker, fiscal_year), 'no violations')
from bad;

-- 3. Revenue must be positive.
with bad as (
    select ticker, fiscal_year from mart.annual_wide where revenue <= 0
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'revenue_is_positive', 'error',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' ' || fiscal_year, ', ' order by ticker, fiscal_year), 'no violations')
from bad;

-- 4. Every company must have revenue data.
with bad as (
    select c.ticker
    from core.dim_company c
    where not exists (select 1 from core.fact_annual f where f.cik = c.cik and f.metric_code = 'revenue')
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'every_company_has_revenue', 'error',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker, ', ' order by ticker), 'no violations')
from bad;

-- 5. One period end per company and fiscal year (a changed year end would break year-over-year growth).
with bad as (
    select ticker, fiscal_year
    from (select c.ticker, f.fiscal_year, count(distinct f.period_end) as periods
          from core.fact_annual f join core.dim_company c on c.cik = f.cik
          group by c.ticker, f.fiscal_year) t
    where periods > 1
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'one_period_end_per_fiscal_year', 'error',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' ' || fiscal_year, ', ' order by ticker, fiscal_year), 'no violations')
from bad;

-- 6. No gaps in the revenue history (a missing year breaks growth rates).
with bad as (
    select c.ticker, (max(f.fiscal_year) - min(f.fiscal_year) + 1) - count(distinct f.fiscal_year) as missing_years
    from core.fact_annual f join core.dim_company c on c.cik = f.cik
    where f.metric_code = 'revenue'
    group by c.ticker
    having (max(f.fiscal_year) - min(f.fiscal_year) + 1) <> count(distinct f.fiscal_year)
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'no_gaps_in_revenue_history', 'warning',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' (' || missing_years || ' missing)', ', ' order by ticker), 'no violations')
from bad;

-- 7. Years with revenue but no net income.
with bad as (
    select ticker, fiscal_year from mart.annual_wide where revenue is not null and net_income is null
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'revenue_without_net_income', 'warning',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' ' || fiscal_year, ', ' order by ticker, fiscal_year), 'no violations')
from bad;

-- 8. The latest report of each company should be less than 15 months old.
with bad as (
    select c.ticker, max(f.period_end) as latest
    from core.fact_annual f join core.dim_company c on c.cik = f.cik
    group by c.ticker
    having max(f.period_end) < current_date - interval '15 months'
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'latest_report_is_recent', 'warning',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' (latest ' || latest || ')', ', ' order by ticker), 'no violations')
from bad;

-- 9. Raw data should only contain USD values for the tags we use.
with bad as (
    select unit, count(*) as n from raw.facts where unit <> 'USD' group by unit
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'raw_units_are_usd', 'warning',
       case when count(*) = 0 then 'pass' else 'fail' end, coalesce(sum(n), 0)::int,
       coalesce(string_agg(unit || ': ' || n, ', '), 'no violations')
from bad;

-- 10. Revenue should not drop by more than 40% or grow by more than 150% in one year.
-- A swing like this is usually a wrong tag or a unit problem, not a real business change.
with bad as (
    select ticker, fiscal_year, revenue_growth_pct from mart.kpis_annual
    where (revenue_growth_pct < -40 or revenue_growth_pct > 150)
      and not exists (select 1 from dq.reviewed_exceptions e
                      where e.check_name = 'revenue_change_is_plausible'
                        and e.ticker = kpis_annual.ticker and e.fiscal_year = kpis_annual.fiscal_year)
)
insert into dq.check_results (check_name, severity, status, issue_count, details)
select 'revenue_change_is_plausible', 'warning',
       case when count(*) = 0 then 'pass' else 'fail' end, count(*),
       coalesce(string_agg(ticker || ' ' || fiscal_year || ' (' || revenue_growth_pct || '%)', ', '
                           order by ticker, fiscal_year), 'no violations')
from bad;

-- Latest run only.
create or replace view dq.latest_checks as
select check_name, severity, status, issue_count, details, run_at
from dq.check_results
where run_at = (select max(run_at) from dq.check_results)
order by status desc, severity, check_name;
