-- olist late deliveries: analysis queries
-- run after 02_clean.sql (uses the clean tables)
-- results and findings are in the README

USE [Project1 -Olist];
GO


-- 1. late rate by month
-- DATEFROMPARTS gives a real date for the month, so it sorts right and works in power bi
-- check: late orders add up to 7822

SELECT
    DATEFROMPARTS(YEAR(o.order_purchase_timestamp),
                  MONTH(o.order_purchase_timestamp), 1) AS order_month,
    COUNT(*) AS orders,
    SUM(o.is_late) AS late_orders,
    CAST(SUM(o.is_late) * 100.0 / COUNT(*) AS decimal(5,1)) AS pct_late,
    CAST(AVG(DATEDIFF(day, o.order_purchase_timestamp, o.order_delivered_customer_date) * 1.0)
         AS decimal(5,1)) AS avg_actual_days,
    CAST(AVG(o.days_late * 1.0) AS decimal(5,1)) AS avg_days_vs_estimate
FROM clean.orders o
GROUP BY DATEFROMPARTS(YEAR(o.order_purchase_timestamp),
                       MONTH(o.order_purchase_timestamp), 1)
ORDER BY order_month;
GO


-- 2. review score by how late the order was
-- the 0. 1. 2. prefixes keep the bands in order
-- join is safe, clean.order_reviews has 1 review per order
-- check: bands add up to 95560

SELECT
    CASE
        WHEN o.days_late <= 0  THEN '0. on time or early'
        WHEN o.days_late <= 3  THEN '1. 1-3 days late'
        WHEN o.days_late <= 7  THEN '2. 4-7 days late'
        WHEN o.days_late <= 14 THEN '3. 8-14 days late'
        ELSE '4. 15+ days late'
    END AS lateness_band,
    COUNT(*) AS orders,
    CAST(AVG(r.review_score * 1.0) AS decimal(3,2)) AS avg_score,
    CAST(SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)
         AS decimal(5,1)) AS pct_one_star
FROM clean.orders o
JOIN clean.order_reviews r
    ON o.order_id = r.order_id
GROUP BY
    CASE
        WHEN o.days_late <= 0  THEN '0. on time or early'
        WHEN o.days_late <= 3  THEN '1. 1-3 days late'
        WHEN o.days_late <= 7  THEN '2. 4-7 days late'
        WHEN o.days_late <= 14 THEN '3. 8-14 days late'
        ELSE '4. 15+ days late'
    END
ORDER BY lateness_band;
GO


-- 3. late rate by state
-- customer_id is unique in clean.customers, so the join doesn't duplicate orders
-- hotspot rule (set before looking): 500+ orders and 12%+ late

SELECT
    c.customer_state,
    COUNT(*) AS orders,
    SUM(o.is_late) AS late_orders,
    CAST(SUM(o.is_late) * 100.0 / COUNT(*) AS decimal(5,1)) AS pct_late
FROM clean.orders o
JOIN clean.customers c
    ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY pct_late DESC;
GO


-- 4. actual vs estimated delivery days by state
-- avg_days_vs_estimate is the buffer: negative = arrived early

SELECT
    c.customer_state,
    COUNT(*) AS orders,
    CAST(AVG(DATEDIFF(day, o.order_purchase_timestamp, o.order_delivered_customer_date) * 1.0)
         AS decimal(5,1)) AS avg_actual_days,
    CAST(AVG(DATEDIFF(day, o.order_purchase_timestamp, o.order_estimated_delivery_date) * 1.0)
         AS decimal(5,1)) AS avg_estimated_days,
    CAST(AVG(o.days_late * 1.0) AS decimal(5,1)) AS avg_days_vs_estimate,
    CAST(SUM(o.is_late) * 100.0 / COUNT(*) AS decimal(5,1)) AS pct_late
FROM clean.orders o
JOIN clean.customers c
    ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY avg_actual_days DESC;
GO
