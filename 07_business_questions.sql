/* ============================================================
   File     : 07_business_questions.sql
   Project  : Retail Sales Analysis (dbo.Sales)
   Purpose  : Ten business questions and the queries that answer
              them. This is the analytical core of the project.
   Depends  : 05_data_cleaning.sql
   Note     : Export each result to /results and summarise the
              answer in docs/findings.md.
   ============================================================ */

USE SalesAnalysis;
GO

-- ------------------------------------------------------------
-- Q1. Which city generates the most revenue, and what share of
--     the company total does it represent?
-- Technique: aggregation + a window function over the grand total
-- ------------------------------------------------------------
SELECT
    City,
    COUNT(*)                                        AS Transactions,
    SUM(Sale)                                       AS Revenue,
    AVG(Sale)                                       AS AvgTicket,
    CAST(100.0 * SUM(Sale) / SUM(SUM(Sale)) OVER () AS DECIMAL(5,2)) AS PctOfRevenue,
    RANK() OVER (ORDER BY SUM(Sale) DESC)           AS RevenueRank
FROM dbo.Sales
GROUP BY City
ORDER BY Revenue DESC;

-- ------------------------------------------------------------
-- Q2. Who is the best rep - by revenue, and by margin?
--     These are usually two different people. That gap is the
--     insight worth writing up.
-- Technique: two RANKs side by side
-- ------------------------------------------------------------
SELECT
    Rep,
    COUNT(*)                                     AS Deals,
    SUM(Sale)                                    AS Revenue,
    SUM(Profit)                                  AS Profit,
    CAST(100.0 * SUM(Profit) / NULLIF(SUM(Sale),0) AS DECIMAL(5,2)) AS MarginPct,
    RANK() OVER (ORDER BY SUM(Sale) DESC)        AS RankByRevenue,
    RANK() OVER (ORDER BY SUM(Profit) DESC)      AS RankByProfit
FROM dbo.Sales
GROUP BY Rep
ORDER BY Revenue DESC;

-- ------------------------------------------------------------
-- Q3. How has revenue moved year over year?
-- Technique: CTE + LAG for the prior-year comparison
-- ------------------------------------------------------------
WITH yearly AS (
    SELECT YEAR(SaleDate) AS SaleYear, SUM(Sale) AS Revenue
    FROM dbo.Sales
    GROUP BY YEAR(SaleDate)
)
SELECT
    SaleYear,
    Revenue,
    LAG(Revenue) OVER (ORDER BY SaleYear)                AS PrevYear,
    Revenue - LAG(Revenue) OVER (ORDER BY SaleYear)      AS Change,
    CAST(100.0 * (Revenue - LAG(Revenue) OVER (ORDER BY SaleYear))
         / NULLIF(LAG(Revenue) OVER (ORDER BY SaleYear), 0) AS DECIMAL(6,2)) AS GrowthPct
FROM yearly
ORDER BY SaleYear;

-- ------------------------------------------------------------
-- Q4. Which months are strongest? Is there a seasonal pattern
--     that repeats across years?
-- Technique: DATENAME + grouping by month number
-- ------------------------------------------------------------
SELECT
    MONTH(SaleDate)                    AS MonthNo,
    DATENAME(MONTH, MIN(SaleDate))     AS MonthName,
    COUNT(*)                           AS Transactions,
    SUM(Sale)                          AS Revenue,
    AVG(Sale)                          AS AvgTicket
FROM dbo.Sales
GROUP BY MONTH(SaleDate)
ORDER BY MonthNo;

-- ------------------------------------------------------------
-- Q5. Which products are high-volume but low-margin?
--     These quietly drain profit.
-- Technique: CASE to bucket the result into a recommendation
-- ------------------------------------------------------------
SELECT
    Prod,
    COUNT(*)     AS UnitsSold,
    SUM(Sale)    AS Revenue,
    SUM(Profit)  AS Profit,
    CAST(100.0 * SUM(Profit) / NULLIF(SUM(Sale),0) AS DECIMAL(5,2)) AS MarginPct,
    CASE
        WHEN COUNT(*) > (SELECT AVG(c) FROM (SELECT COUNT(*) c FROM dbo.Sales GROUP BY Prod) x)
         AND 100.0 * SUM(Profit) / NULLIF(SUM(Sale),0) < 20 THEN 'High volume, thin margin - review pricing'
        WHEN 100.0 * SUM(Profit) / NULLIF(SUM(Sale),0) >= 40 THEN 'Premium - protect'
        ELSE 'Standard'
    END AS Assessment
FROM dbo.Sales
GROUP BY Prod
ORDER BY Revenue DESC;

-- ------------------------------------------------------------
-- Q6. Running total of revenue by month (cumulative view).
-- Technique: SUM() OVER with ROWS UNBOUNDED PRECEDING
-- ------------------------------------------------------------
WITH monthly AS (
    SELECT
        DATEFROMPARTS(YEAR(SaleDate), MONTH(SaleDate), 1) AS MonthStart,
        SUM(Sale) AS Revenue
    FROM dbo.Sales
    GROUP BY DATEFROMPARTS(YEAR(SaleDate), MONTH(SaleDate), 1)
)
SELECT
    MonthStart,
    Revenue,
    SUM(Revenue) OVER (ORDER BY MonthStart ROWS UNBOUNDED PRECEDING) AS RunningTotal,
    AVG(Revenue) OVER (ORDER BY MonthStart ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS Rolling3MonthAvg
FROM monthly
ORDER BY MonthStart;

-- ------------------------------------------------------------
-- Q7. Top 3 products in each city.
-- Technique: ROW_NUMBER partitioned by city, filtered in a CTE
-- ------------------------------------------------------------
WITH ranked AS (
    SELECT
        City,
        Prod,
        SUM(Sale) AS Revenue,
        ROW_NUMBER() OVER (PARTITION BY City ORDER BY SUM(Sale) DESC) AS rn
    FROM dbo.Sales
    GROUP BY City, Prod
)
SELECT City, rn AS Position, Prod, Revenue
FROM ranked
WHERE rn <= 3
ORDER BY City, Position;

-- ------------------------------------------------------------
-- Q8. Do the top 20% of transactions generate 80% of revenue?
-- Technique: NTILE + cumulative share
-- ------------------------------------------------------------
WITH ranked AS (
    SELECT Sale, NTILE(5) OVER (ORDER BY Sale DESC) AS Quintile
    FROM dbo.Sales
)
SELECT
    Quintile,
    COUNT(*)   AS Transactions,
    SUM(Sale)  AS Revenue,
    CAST(100.0 * SUM(Sale) / SUM(SUM(Sale)) OVER () AS DECIMAL(5,2)) AS PctOfRevenue
FROM ranked
GROUP BY Quintile
ORDER BY Quintile;

-- ------------------------------------------------------------
-- Q9. City x Year revenue matrix (pivot for a report table).
-- Technique: conditional aggregation - portable and readable
-- ------------------------------------------------------------
SELECT
    City,
    SUM(CASE WHEN YEAR(SaleDate) BETWEEN 2004 AND 2007 THEN Sale ELSE 0 END) AS [2004-2007],
    SUM(CASE WHEN YEAR(SaleDate) BETWEEN 2008 AND 2011 THEN Sale ELSE 0 END) AS [2008-2011],
    SUM(CASE WHEN YEAR(SaleDate) BETWEEN 2012 AND 2015 THEN Sale ELSE 0 END) AS [2012-2015],
    SUM(Sale) AS Total
FROM dbo.Sales
GROUP BY City
ORDER BY Total DESC;

-- ------------------------------------------------------------
-- Q10. Which rep-city pairings beat that city's average ticket?
--      Answers "where is this person actually strong?"
-- Technique: window function partitioned by city, compared to
--            the rep-level figure
-- ------------------------------------------------------------
WITH repCity AS (
    SELECT
        City,
        Rep,
        AVG(Sale) AS RepAvgTicket,
        SUM(Sale) AS Revenue,
        COUNT(*)  AS Deals
    FROM dbo.Sales
    GROUP BY City, Rep
)
SELECT
    City,
    Rep,
    Deals,
    Revenue,
    CAST(RepAvgTicket AS DECIMAL(12,2))                          AS RepAvgTicket,
    CAST(AVG(RepAvgTicket) OVER (PARTITION BY City) AS DECIMAL(12,2)) AS CityAvgTicket,
    CASE WHEN RepAvgTicket > AVG(RepAvgTicket) OVER (PARTITION BY City)
         THEN 'Above city average' ELSE 'Below city average' END AS Standing
FROM repCity
ORDER BY City, RepAvgTicket DESC;
