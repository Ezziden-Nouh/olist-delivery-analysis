-- olist late deliveries: first look at the raw data
-- raw tables in dbo, nothing changed here
-- findings are in the README

USE [Project1 -Olist];
GO


-- row counts for all tables (check the import worked)
SELECT t.name AS table_name, SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
GROUP BY t.name
ORDER BY t.name;

-- previews of each table
SELECT TOP 100 * FROM olist_orders_dataset;
SELECT TOP 100 * FROM olist_customers_dataset;
SELECT TOP 100 * FROM olist_order_items_dataset;
SELECT TOP 100 * FROM olist_order_payments_dataset;
SELECT TOP 100 * FROM olist_order_reviews_dataset;
SELECT TOP 100 * FROM olist_products_dataset;
SELECT TOP 100 * FROM olist_sellers_dataset;
SELECT TOP 100 * FROM product_category_name_translation;


-- 1. date range of orders
SELECT 
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM olist_orders_dataset;

-- 2. orders by status
SELECT 
    order_status, 
    COUNT(*) AS n
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY n DESC;

-- 3. missing delivery dates
SELECT 
    COUNT(*) AS total,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS no_delivery_date
FROM olist_orders_dataset;

-- 4. orders per month (looking for thin months at the start and end)
SELECT 
    FORMAT(order_purchase_timestamp, 'yyyy-MM') AS [month], 
    COUNT(*) AS orders
FROM olist_orders_dataset
GROUP BY FORMAT(order_purchase_timestamp, 'yyyy-MM')
ORDER BY [month];

-- 5. orders marked delivered but with no delivery date
SELECT 
    COUNT(*) AS delivered_without_date
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- 6. on time vs late, delivered orders only
SELECT
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'on time or early'
        ELSE 'late'
    END AS delivery_result,
    COUNT(*) AS orders
FROM olist_orders_dataset
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL
GROUP BY
    CASE
        WHEN order_delivered_customer_date <= order_estimated_delivery_date THEN 'on time or early'
        ELSE 'late'
    END;

-- 7. review score distribution
SELECT 
    review_score, 
    COUNT(*) AS reviews
FROM olist_order_reviews_dataset
GROUP BY review_score
ORDER BY review_score;

-- 8. review score for late vs on time orders
-- quick check only: orders with 2 reviews are counted twice here (fixed in 02_clean.sql)
SELECT
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'on time or early'
        ELSE 'late'
    END AS delivery_result,
    COUNT(*) AS orders,
    AVG(CAST(r.review_score AS DECIMAL(4, 2))) AS avg_score,
    SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_one_star
FROM olist_orders_dataset o
JOIN olist_order_reviews_dataset r 
    ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY
    CASE
        WHEN o.order_delivered_customer_date <= o.order_estimated_delivery_date THEN 'on time or early'
        ELSE 'late'
    END;

-- 9. repeat customers (customer_unique_id is the real person, customer_id is per order)
SELECT 
    COUNT(*) AS customers,
    SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) AS repeat_customers
FROM (
    SELECT 
        c.customer_unique_id, 
        COUNT(*) AS n_orders
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c 
        ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
) t;