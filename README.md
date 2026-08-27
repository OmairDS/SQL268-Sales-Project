# Retail Sales Analysis (SQL Server / T-SQL)

T-SQL analysis of ~1,990 retail transactions (2004–2015) across six Saudi cities, five sales representatives, and multiple stores and product lines. The project covers the full pipeline: database creation, data loading, a documented data-quality audit, cleaning, exploratory profiling, ten business questions, and reusable views and stored procedures.

> **Reference implementation for the SQL track.** Build your own repository to this standard — see [`docs/HOW_TO_USE_THIS_REPO.md`](docs/HOW_TO_USE_THIS_REPO.md).

---

## Business questions answered

1. Which city generates the most revenue, and what share of the total?
2. Who is the best rep — by revenue, and by margin? (Usually two different people.)
3. How has revenue moved year over year?
4. Is there a repeating seasonal pattern?
5. Which products are high-volume but low-margin?
6. What does the cumulative revenue curve look like month by month?
7. What are the top three products in each city?
8. Do the top 20% of transactions produce 80% of revenue?
9. How does each city compare across four-year periods?
10. Which rep–city pairings beat that city's average transaction value?

Answers with numbers: [`docs/findings.md`](docs/findings.md)

---

## Dataset

`SQL-268.csv` → `dbo.Sales`, ~1,990 rows, 2004–2015, currency SAR.

| Column | Type | Description |
|---|---|---|
| `SaleID` | INT | Transaction identifier (**not unique** — see below) |
| `SaleDate` | DATE | Date of sale |
| `City` | VARCHAR(50) | Dammam, Riyadh, Jeddah, Abha, Hail, Jubail |
| `Rep` | VARCHAR(50) | Yahia, Mjeed, Abdul, Maliha, Ghalia |
| `Store` | VARCHAR(50) | Retail outlet |
| `Prod` | VARCHAR(50) | Product sold |
| `Cost` | DECIMAL(12,2) | Cost of goods |
| `Sale` | DECIMAL(12,2) | Sale value |
| `Profit` | DECIMAL(12,2) | Computed column: `Sale - Cost` |

Full column notes and issue log: [`data/data_dictionary.md`](data/data_dictionary.md)

---

## Data quality issues found and fixed

The audit script proves each issue before anything is changed. The raw CSV is never edited — all cleaning is code, in version control, and repeatable.

| Issue | Evidence | Impact if ignored | Fix |
|---|---|---|---|
| `Mjeeed` should be `Mjeed` | SaleID 3 | One rep split into two — every rep ranking is wrong | Mapped in [`05_data_cleaning.sql`](sql/05_data_cleaning.sql) |
| `Lulu Hyper` vs `Lulu` | SaleID 3 | Same outlet counted twice | Standardised to `Lulu` |
| Duplicate `SaleID` | SaleID 3 | `SaleID` unusable as a primary key | Surrogate key `SaleKey IDENTITY` |
| Leading/trailing spaces | Text columns | `GROUP BY` splits groups silently | `LTRIM(RTRIM())` on load |
| Non-numeric values in money columns | `Cost`, `Sale` | `INSERT` aborts or values become NULL | `TRY_CONVERT` + rejection filter |

Reproduce the evidence: [`04_data_quality_audit.sql`](sql/04_data_quality_audit.sql)

---

## How to run

Execute in order in SSMS or Azure Data Studio against SQL Server 2019+:

```
sql/01_create_database.sql        -- creates SalesAnalysis
sql/02_create_tables.sql          -- staging + typed table + indexes
sql/03_load_data.sql              -- EDIT THE FILE PATH FIRST
sql/04_data_quality_audit.sql     -- read-only; screenshot the output
sql/05_data_cleaning.sql          -- applies fixes, populates dbo.Sales
sql/06_exploratory_analysis.sql   -- profiling
sql/07_business_questions.sql     -- the ten answers
sql/08_views_and_procedures.sql   -- views + stored procedure
```

Scripts are idempotent — safe to re-run from the top on a clean database.

---

## Sample queries

**Q2 — revenue rank vs profit rank, side by side**

```sql
SELECT
    Rep,
    SUM(Sale)                                    AS Revenue,
    SUM(Profit)                                  AS Profit,
    CAST(100.0 * SUM(Profit) / NULLIF(SUM(Sale),0) AS DECIMAL(5,2)) AS MarginPct,
    RANK() OVER (ORDER BY SUM(Sale) DESC)        AS RankByRevenue,
    RANK() OVER (ORDER BY SUM(Profit) DESC)      AS RankByProfit
FROM dbo.Sales
GROUP BY Rep
ORDER BY Revenue DESC;
```

**The cleaning fix that changes the answer**

```sql
-- 'Mjeeed' is 'Mjeed' with an extra e. Left alone, it splits one
-- rep across two rows in every report above.
CASE WHEN LTRIM(RTRIM(Rep)) = 'Mjeeed' THEN 'Mjeed'
     ELSE LTRIM(RTRIM(Rep)) END AS Rep
```

<details>
<summary>Q3 — year-over-year growth with LAG</summary>

```sql
WITH yearly AS (
    SELECT YEAR(SaleDate) AS SaleYear, SUM(Sale) AS Revenue
    FROM dbo.Sales
    GROUP BY YEAR(SaleDate)
)
SELECT
    SaleYear,
    Revenue,
    LAG(Revenue) OVER (ORDER BY SaleYear)           AS PrevYear,
    CAST(100.0 * (Revenue - LAG(Revenue) OVER (ORDER BY SaleYear))
         / NULLIF(LAG(Revenue) OVER (ORDER BY SaleYear), 0) AS DECIMAL(6,2)) AS GrowthPct
FROM yearly
ORDER BY SaleYear;
```

</details>

All queries: [`sql/`](sql/)

---

## Key findings

> Fill this in from your own results. Every bullet needs a real number.

- ___ leads revenue at ___% of the total, but ___ has the highest average ticket at SAR ___.
- ___ ranks #___ on revenue and #___ on profit — volume is masking margin.
- Revenue changed ___% between 2004 and 2015, with a visible dip in ___.
- The top 20% of transactions account for ___% of revenue.

![Revenue trend](results/screenshots/yearly_trend.png)

---

## Techniques used

Aggregation · `GROUP BY` / `HAVING` · CTEs · window functions (`RANK`, `ROW_NUMBER`, `LAG`, `NTILE`, running totals, moving averages) · `PERCENTILE_CONT` · conditional aggregation (pivot) · `CASE` expressions · date functions (`DATEFROMPARTS`, `DATENAME`, `DATEDIFF`) · `TRY_CONVERT` for safe type handling · computed persisted columns · indexing · views · parameterised stored procedure

---

## Repository structure

| Path | Contents |
|---|---|
| `sql/` | Eight numbered scripts, run in order |
| `data/` | Raw CSV and the data dictionary |
| `results/` | Exported query results and chart screenshots |
| `docs/` | Written findings and trainee instructions |
| `.gitignore` | Blocks credentials, `.bak`, `.mdf` and editor noise |

---

## Author

Your Name · [LinkedIn](https://www.linkedin.com/in/alomairabdulds/) · Omairdata@outlook.com
