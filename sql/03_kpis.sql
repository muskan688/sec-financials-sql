-- Analysis views. Power BI connects to the mart schema.

-- One row per company and fiscal year, one column per metric (pivot with conditional aggregation).
create or replace view mart.annual_wide as
select c.cik,
       c.ticker,
       c.name,
       c.sector,
       f.fiscal_year,
       max(f.period_end)                                                  as period_end,
       max(f.value) filter (where f.metric_code = 'revenue')              as revenue,
       max(f.value) filter (where f.metric_code = 'gross_profit')         as gross_profit,
       max(f.value) filter (where f.metric_code = 'operating_income')     as operating_income,
       max(f.value) filter (where f.metric_code = 'net_income')           as net_income,
       max(f.value) filter (where f.metric_code = 'operating_cash_flow')  as operating_cash_flow,
       max(f.value) filter (where f.metric_code = 'capex')                as capex,
       max(f.value) filter (where f.metric_code = 'total_assets')         as total_assets,
       max(f.value) filter (where f.metric_code = 'total_liabilities')    as total_liabilities,
       max(f.value) filter (where f.metric_code = 'shareholders_equity')  as shareholders_equity,
       max(f.value) filter (where f.metric_code = 'cash')                 as cash
from core.fact_annual f
join core.dim_company c on c.cik = f.cik
group by c.cik, c.ticker, c.name, c.sector, f.fiscal_year;

-- KPIs per company and year. Growth is only calculated when the previous year is really the year before.
create or replace view mart.kpis_annual as
with lagged as (
    select w.*,
           lag(fiscal_year)    over (partition by cik order by fiscal_year)    as prev_year,
           lag(revenue)        over (partition by cik order by fiscal_year)    as prev_revenue,
           lag(net_income)     over (partition by cik order by fiscal_year)    as prev_net_income,
           lag(fiscal_year, 3) over (partition by cik order by fiscal_year)    as year_3_back,
           lag(revenue, 3)     over (partition by cik order by fiscal_year)    as revenue_3_back
    from mart.annual_wide w
),
calc as (
    select cik, ticker, name, sector, fiscal_year, period_end,
           revenue, gross_profit, operating_income, net_income,
           operating_cash_flow, capex, total_assets, total_liabilities, shareholders_equity, cash,
           case when prev_year = fiscal_year - 1 and prev_revenue > 0
                then round(100 * (revenue - prev_revenue) / prev_revenue, 1) end                      as revenue_growth_pct,
           case when prev_year = fiscal_year - 1 and prev_net_income > 0
                then round(100 * (net_income - prev_net_income) / prev_net_income, 1) end              as net_income_growth_pct,
           case when year_3_back = fiscal_year - 3 and revenue_3_back > 0 and revenue > 0
                then round(100 * (power(revenue / revenue_3_back, 1.0 / 3) - 1), 1) end                as revenue_cagr_3y_pct,
           round(100 * gross_profit / nullif(revenue, 0), 1)                                           as gross_margin_pct,
           round(100 * operating_income / nullif(revenue, 0), 1)                                       as operating_margin_pct,
           round(100 * net_income / nullif(revenue, 0), 1)                                             as net_margin_pct,
           round(100 * net_income / nullif(shareholders_equity, 0), 1)                                 as return_on_equity_pct,
           round(100 * net_income / nullif(total_assets, 0), 1)                                        as return_on_assets_pct,
           round(total_liabilities / nullif(shareholders_equity, 0), 2)                                as liabilities_to_equity,
           operating_cash_flow - capex                                                                 as free_cash_flow
    from lagged
)
select calc.*,
       round(100 * free_cash_flow / nullif(revenue, 0), 1)                                             as fcf_margin_pct,
       rank() over (partition by fiscal_year order by net_margin_pct desc nulls last)                  as net_margin_rank,
       round(avg(net_margin_pct) over (partition by cik order by fiscal_year
                                       rows between 2 preceding and current row), 1)                   as net_margin_3y_avg_pct
from calc;

-- Sector summary per year (GROUP BY with an aggregate and a median).
create or replace view mart.sector_summary as
select sector,
       fiscal_year,
       count(*)                                                       as companies,
       sum(revenue)                                                   as total_revenue,
       round(avg(net_margin_pct), 1)                                  as avg_net_margin_pct,
       round((percentile_cont(0.5) within group (order by net_margin_pct))::numeric, 1) as median_net_margin_pct
from mart.kpis_annual
where revenue is not null
group by sector, fiscal_year;
