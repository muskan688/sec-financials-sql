-- Schemas and tables. Safe to run more than once.
create schema if not exists raw;    -- data as downloaded, no cleaning
create schema if not exists core;   -- cleaned tables: dimensions and annual facts
create schema if not exists mart;   -- views used for analysis and Power BI
create schema if not exists dq;     -- data quality check results

create table if not exists raw.facts (
    cik         integer not null,
    tag         text    not null,
    unit        text    not null,
    start_date  date,               -- null for balance sheet items (a point in time)
    end_date    date    not null,
    val         numeric not null,
    accn        text,               -- SEC accession number of the filing
    fy          integer,            -- fiscal year of the FILING, not of the period
    fp          text,
    form        text,
    filed       date,
    frame       text
);
create index if not exists ix_raw_facts_lookup on raw.facts (cik, tag, end_date);

create table if not exists core.dim_company (
    cik     integer primary key,
    ticker  text not null unique,
    name    text not null,
    sector  text not null
);

create table if not exists core.dim_metric (
    metric_code text primary key,
    kind        text not null check (kind in ('flow', 'instant')),  -- flow = over a year, instant = at year end
    description text not null
);

create table if not exists core.metric_tag_map (
    tag         text primary key,
    metric_code text    not null references core.dim_metric (metric_code),
    priority    integer not null    -- lower number wins when a company reports several tags for one metric
);

create table if not exists core.fact_annual (
    cik         integer not null references core.dim_company (cik),
    metric_code text    not null references core.dim_metric (metric_code),
    period_end  date    not null,
    fiscal_year integer not null,
    value       numeric not null,   -- USD
    source_tag  text    not null,
    source_accn text,
    filed       date,
    primary key (cik, metric_code, period_end)
);

-- Findings that were checked by hand and are real, not data errors. Checks skip these rows.
create table if not exists dq.reviewed_exceptions (
    check_name  text    not null,
    ticker      text    not null,
    fiscal_year integer not null,
    reason      text    not null,
    primary key (check_name, ticker, fiscal_year)
);

create table if not exists dq.check_results (
    id          bigserial primary key,
    run_at      timestamptz not null default now(),
    check_name  text    not null,
    severity    text    not null check (severity in ('error', 'warning')),
    status      text    not null check (status in ('pass', 'fail')),
    issue_count integer not null,
    details     text
);
