-- Analysis queries. Each block starts with a business question.
-- Run all of them with: python -m src.run_queries
-- "Latest common year" = the newest fiscal year that every company has reported.

-- Q1. Which companies had the highest revenue in the latest common year? (join, ORDER BY)
select ticker, name, sector, round(revenue / 1e9, 1) as revenue_bn
from mart.annual_wide
where fiscal_year = (select min(last_year) from (select max(fiscal_year) as last_year from mart.annual_wide group by cik) t)
order by revenue desc
limit 5;

-- Q2. Which companies grew revenue fastest over the last 3 years? (CAGR from the view, ranked with a window function)
select ticker, fiscal_year, revenue_cagr_3y_pct,
       rank() over (order by revenue_cagr_3y_pct desc) as growth_rank
from mart.kpis_annual
where fiscal_year = (select min(last_year) from (select max(fiscal_year) as last_year from mart.annual_wide group by cik) t)
  and revenue_cagr_3y_pct is not null
order by growth_rank;

-- Q3. Which sector earned the highest median net margin in the latest common year? (GROUP BY, median)
select sector, companies, median_net_margin_pct, round(total_revenue / 1e9, 0) as total_revenue_bn
from mart.sector_summary
where fiscal_year = (select min(last_year) from (select max(fiscal_year) as last_year from mart.annual_wide group by cik) t)
order by median_net_margin_pct desc;

-- Q4. Which companies improved their net margin three years in a row? (LAG in a CTE)
with m as (
    select ticker, fiscal_year, net_margin_pct,
           lag(net_margin_pct, 1) over w as m1,
           lag(net_margin_pct, 2) over w as m2,
           lag(net_margin_pct, 3) over w as m3
    from mart.kpis_annual
    window w as (partition by ticker order by fiscal_year)
)
select ticker, fiscal_year, m3 as margin_3y_ago, net_margin_pct as margin_now
from m
where net_margin_pct > m1 and m1 > m2 and m2 > m3
  and fiscal_year = (select min(last_year) from (select max(fiscal_year) as last_year from mart.annual_wide group by cik) t)
order by ticker;

-- Q5. What was each company's worst revenue year? (ROW_NUMBER per company)
with ranked as (
    select ticker, fiscal_year, revenue_growth_pct,
           row_number() over (partition by ticker order by revenue_growth_pct) as rn
    from mart.kpis_annual
    where revenue_growth_pct is not null
)
select ticker, fiscal_year as worst_year, revenue_growth_pct
from ranked
where rn = 1
order by revenue_growth_pct;

-- Q6. How much of each sector's revenue does each company make? (window SUM per sector)
select sector, ticker,
       round(revenue / 1e9, 1) as revenue_bn,
       round(100 * revenue / sum(revenue) over (partition by sector), 1) as share_of_sector_pct
from mart.annual_wide
where fiscal_year = (select min(last_year) from (select max(fiscal_year) as last_year from mart.annual_wide group by cik) t)
order by sector, share_of_sector_pct desc;

-- Q7. Which companies turn profit into cash best? Free cash flow divided by net income. (derived metric)
select ticker, fiscal_year,
       round(free_cash_flow / 1e9, 1) as fcf_bn,
       round(net_income / 1e9, 1)     as net_income_bn,
       round(free_cash_flow / nullif(net_income, 0), 2) as cash_conversion
from mart.kpis_annual
where fiscal_year = (select min(last_year) from (select max(fiscal_year) as last_year from mart.annual_wide group by cik) t)
  and net_income > 0 and free_cash_flow is not null
order by cash_conversion desc;

-- Q8. Cumulative revenue over the last 5 years per company. (running SUM with a window frame)
select ticker, fiscal_year, round(revenue / 1e9, 1) as revenue_bn,
       round(sum(revenue) over (partition by ticker order by fiscal_year
                                rows between 4 preceding and current row) / 1e9, 1) as revenue_5y_sum_bn
from mart.annual_wide
where ticker in ('AAPL', 'XOM') and fiscal_year >= 2020
order by ticker, fiscal_year;

-- Q9. Which company-years had high return on equity AND high leverage? (filter on two derived KPIs)
-- High ROE can come from debt or from buybacks that shrink equity, not only from strong profits.
select ticker, fiscal_year, return_on_equity_pct, liabilities_to_equity, net_margin_pct
from mart.kpis_annual
where return_on_equity_pct > 30 and liabilities_to_equity > 3
order by fiscal_year desc, return_on_equity_pct desc
limit 10;

-- Q10. Where did net income and operating cash flow move in opposite directions? (compare two lagged series)
with c as (
    select ticker, fiscal_year, net_income, operating_cash_flow,
           lag(net_income) over (partition by ticker order by fiscal_year)         as prev_ni,
           lag(operating_cash_flow) over (partition by ticker order by fiscal_year) as prev_ocf
    from mart.annual_wide
)
select ticker, fiscal_year,
       round(prev_ni / 1e9, 1) as ni_prev_bn, round(net_income / 1e9, 1) as ni_bn,
       round(prev_ocf / 1e9, 1) as ocf_prev_bn, round(operating_cash_flow / 1e9, 1) as ocf_bn
from c
where fiscal_year >= 2020
  and sign(net_income - prev_ni) <> sign(operating_cash_flow - prev_ocf)
order by fiscal_year desc, ticker;

-- Q11. Which companies have the longest revenue history, and which metrics are missing most often? (data coverage)
select c.ticker,
       count(distinct f.fiscal_year) filter (where f.metric_code = 'revenue')      as revenue_years,
       count(distinct f.fiscal_year) filter (where f.metric_code = 'gross_profit') as gross_profit_years,
       count(distinct f.fiscal_year) filter (where f.metric_code = 'capex')        as capex_years
from core.fact_annual f
join core.dim_company c on c.cik = f.cik
group by c.ticker
order by revenue_years desc, c.ticker;

-- Q12. Which filing and tag did each revenue number come from? (lineage, 2 joins)
select c.ticker, f.fiscal_year, f.source_tag, f.source_accn, f.filed
from core.fact_annual f
join core.dim_company c on c.cik = f.cik
where f.metric_code = 'revenue' and c.ticker in ('AMZN', 'AAPL') and f.fiscal_year in (2017, 2018, 2019)
order by c.ticker, f.fiscal_year;
