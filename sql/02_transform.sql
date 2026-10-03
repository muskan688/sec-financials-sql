-- Build core.fact_annual from raw.facts. Rebuilds the table every run.

truncate core.fact_annual;
delete from core.metric_tag_map;
delete from core.dim_metric;

insert into core.dim_metric (metric_code, kind, description) values
    ('revenue',               'flow',    'Total revenue for the fiscal year'),
    ('gross_profit',          'flow',    'Revenue minus cost of revenue'),
    ('operating_income',      'flow',    'Operating income or loss'),
    ('net_income',            'flow',    'Net income or loss'),
    ('operating_cash_flow',   'flow',    'Net cash from operating activities'),
    ('capex',                 'flow',    'Payments for property, plant and equipment (positive number)'),
    ('total_assets',          'instant', 'Total assets at fiscal year end'),
    ('total_liabilities',     'instant', 'Total liabilities at fiscal year end'),
    ('shareholders_equity',   'instant', 'Stockholders equity at fiscal year end'),
    ('liabilities_and_equity','instant', 'Total liabilities and equity at fiscal year end'),
    ('cash',                  'instant', 'Cash and cash equivalents at fiscal year end');

-- Companies label revenue with different tags, and some switched tags over time
-- (for example after the 2018 revenue accounting standard). The lowest priority number wins per year.
insert into core.metric_tag_map (tag, metric_code, priority) values
    ('RevenueFromContractWithCustomerExcludingAssessedTax', 'revenue', 1),
    ('Revenues',                                            'revenue', 2),
    ('RevenueFromContractWithCustomerIncludingAssessedTax', 'revenue', 3),
    ('SalesRevenueNet',                                     'revenue', 4),
    ('SalesRevenueGoodsNet',                                'revenue', 5),
    ('GrossProfit',                                         'gross_profit', 1),
    ('OperatingIncomeLoss',                                 'operating_income', 1),
    ('NetIncomeLoss',                                       'net_income', 1),
    ('ProfitLoss',                                          'net_income', 2),  -- fallback; includes minority interests
    ('NetCashProvidedByUsedInOperatingActivities',          'operating_cash_flow', 1),
    ('PaymentsToAcquirePropertyPlantAndEquipment',          'capex', 1),
    ('PaymentsToAcquireProductiveAssets',                   'capex', 2),  -- used by some companies instead
    ('Assets',                                              'total_assets', 1),
    ('Liabilities',                                         'total_liabilities', 1),
    ('StockholdersEquity',                                  'shareholders_equity', 1),
    ('LiabilitiesAndStockholdersEquity',                    'liabilities_and_equity', 1),
    ('CashAndCashEquivalentsAtCarryingValue',               'cash', 1);

-- Keep only annual figures from 10-K filings, in USD.
--   flow items:    the period must last about one year (350 to 380 days; 52/53 week years fit)
--   instant items: no start date, and the date must be the end of an annual period in the same filing
--                  (10-K notes also report balance sheet items for other dates, for example subsidiaries)
-- Values are "as originally reported": for each company, metric and period end we use the earliest
-- 10-K that reports it, and inside that filing the tag with the lowest priority number.
-- One guard for revenue: a tag whose value is below half of the largest revenue figure in the same
-- filing is ignored, because it is a sub-total (P&G FY2014 tags 29.4bn as "Revenues" next to 83.1bn of sales).
-- This keeps every number of one year from the same filing, so the balance sheet balances.
-- Later restatements are ignored on purpose.
insert into core.fact_annual (cik, metric_code, period_end, fiscal_year, value, source_tag, source_accn, filed)
with annual_periods as (
    select distinct cik, accn, end_date
    from raw.facts
    where form in ('10-K', '10-K/A') and unit = 'USD'
      and start_date is not null and end_date - start_date between 350 and 380
),
candidates as (
    select f.cik, m.metric_code, f.end_date as period_end, f.val, f.tag, f.accn, f.filed, m.priority
    from raw.facts f
    join core.metric_tag_map m on m.tag = f.tag
    join core.dim_metric d     on d.metric_code = m.metric_code
    join core.dim_company c    on c.cik = f.cik
    where f.unit = 'USD'
      and f.form in ('10-K', '10-K/A')
      and (   (d.kind = 'flow'    and f.start_date is not null and f.end_date - f.start_date between 350 and 380)
           or (d.kind = 'instant' and f.start_date is null
               and exists (select 1 from annual_periods a
                           where a.cik = f.cik and a.accn = f.accn and a.end_date = f.end_date)))
),
sized as (
    select *,
           max(val) over (partition by cik, metric_code, accn, period_end) as max_val_in_filing
    from candidates
),
ranked as (
    select *,
           row_number() over (partition by cik, metric_code, period_end
                              order by filed, priority, accn) as rn
    from sized
    where metric_code <> 'revenue' or val >= 0.5 * max_val_in_filing
)
select cik,
       metric_code,
       period_end,
       -- A year ending in January (retailers) belongs to the previous calendar year,
       -- so fiscal_year is the calendar year in which most of the fiscal year falls.
       extract(year from period_end - interval '45 days')::int,
       val,
       tag,
       accn,
       filed
from ranked
where rn = 1;
