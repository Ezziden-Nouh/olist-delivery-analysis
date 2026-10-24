---- olist late deliveries: cleaning
-- builds clean copies of the tables in a separate schema, raw dbo tables stay untouched
-- cleaning rules and counts are in the README

USE [Project1 -Olist];
GO


-- create the clean schema if it's not there
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'clean')
BEGIN
    EXEC('CREATE SCHEMA clean');
END
GO


-- orders: delivered only, with a delivery date, jan 2017 to aug 2018
-- days_late = delivered minus estimated (negative = early), is_late = 1 if late
DROP TABLE IF EXISTS clean.orders;
GO

SELECT
    o.order_id,
    o.customer_id,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATEDIFF(day, o.order_estimated_delivery_date, o.order_delivered_customer_date) AS days_late,
    CASE 
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 
        ELSE 0 
    END AS is_late
INTO clean.orders
FROM dbo.olist_orders_dataset o
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp <  '2018-09-01';
GO

-- check: 96203 orders, 7822 late
SELECT COUNT(*) AS orders, SUM(is_late) AS late_orders FROM clean.orders;


-- reviews: some orders have more than one review, keep the latest one
-- check: 547 orders with multiple reviews
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (SELECT order_id FROM dbo.olist_order_reviews_dataset
      GROUP BY order_id HAVING COUNT(*) > 1) t;

DROP TABLE IF EXISTS clean.order_reviews;
GO

WITH ranked AS (
    SELECT
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_creation_date,
        r.review_answer_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY r.review_answer_timestamp DESC
        ) AS rn
    FROM dbo.olist_order_reviews_dataset r
    WHERE r.order_id IN (SELECT order_id FROM clean.orders)
)
SELECT review_id, order_id, review_score, review_creation_date, review_answer_timestamp
INTO clean.order_reviews
FROM ranked
WHERE rn = 1;
GO

-- check: both 95560 = one review per order (643 delivered orders have no review)
SELECT COUNT(*) AS reviews, COUNT(DISTINCT order_id) AS distinct_orders
FROM clean.order_reviews;


-- customers: customer_id is per order, customer_unique_id is the real person
DROP TABLE IF EXISTS clean.customers;
GO

SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state
INTO clean.customers
FROM dbo.olist_customers_dataset c
WHERE c.customer_id IN (SELECT customer_id FROM clean.orders);
GO

-- check: 96203 rows, 96203 customer_ids, 93096 people
SELECT
    COUNT(*) AS customer_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(DISTINCT customer_unique_id) AS distinct_people
FROM clean.customers;


-- order items: one row per item, an order can have several
DROP TABLE IF EXISTS clean.order_items;
GO

SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    i.shipping_limit_date,
    i.price,
    i.freight_value
INTO clean.order_items
FROM dbo.olist_order_items_dataset i
WHERE i.order_id IN (SELECT order_id FROM clean.orders);
GO

-- check: 109872 items, all 96203 orders, 0 bad prices
SELECT
    COUNT(*) AS item_rows,
    COUNT(DISTINCT order_id) AS distinct_orders,
    SUM(CASE WHEN price IS NULL OR price <= 0 THEN 1 ELSE 0 END) AS bad_prices
FROM clean.order_items;


-- products: english category names, LEFT JOIN so products without a translation don't disappear
DROP TABLE IF EXISTS clean.products;
GO

SELECT
    p.product_id,
    p.product_category_name AS category_pt,
    COALESCE(t.product_category_name_english,
             p.product_category_name,
             'unknown') AS category,
    p.product_weight_g
INTO clean.products
FROM dbo.olist_products_dataset p
LEFT JOIN dbo.product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_id IN (SELECT product_id FROM clean.order_items);
GO

-- check: 32079 products, 584 with no category
-- note: untranslated came out as 1993 but that's wrong, it also counts categories
-- that are already english (cool_stuff, pet_shop...). the query below shows the real one
SELECT
    COUNT(*) AS product_rows,
    COUNT(DISTINCT product_id) AS distinct_products,
    SUM(CASE WHEN category_pt IS NULL THEN 1 ELSE 0 END) AS no_category,
    SUM(CASE WHEN category_pt IS NOT NULL AND category = category_pt THEN 1 ELSE 0 END) AS untranslated
FROM clean.products;

SELECT category_pt, COUNT(*) AS products
FROM clean.products
WHERE category_pt IS NOT NULL
  AND category = category_pt
GROUP BY category_pt
ORDER BY products DESC;

-- only real gap: this category is missing from olist's translation table (9 products)
UPDATE clean.products
SET category = 'portable_kitchen_food_preparers'
WHERE category_pt = 'portateis_cozinha_e_preparadores_de_alimentos';


-- sellers: only the ones with items in the clean orders
DROP TABLE IF EXISTS clean.sellers;
GO

SELECT
    s.seller_id,
    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state
INTO clean.sellers
FROM dbo.olist_sellers_dataset s
WHERE s.seller_id IN (SELECT seller_id FROM clean.order_items);
GO

-- check: 2945 sellers
SELECT
    COUNT(*) AS seller_rows,
    COUNT(DISTINCT seller_id) AS distinct_sellers
FROM clean.sellers;


-- final check: nothing points to a missing row, all 4 should be 0
-- NOT EXISTS instead of NOT IN because NOT IN breaks if there's a NULL
SELECT
    (SELECT COUNT(*) FROM clean.orders o
     WHERE NOT EXISTS (SELECT 1 FROM clean.customers c WHERE c.customer_id = o.customer_id))
        AS orders_without_customer,

    (SELECT COUNT(*) FROM clean.order_items i
     WHERE NOT EXISTS (SELECT 1 FROM clean.products p WHERE p.product_id = i.product_id))
        AS items_without_product,

    (SELECT COUNT(*) FROM clean.order_items i
     WHERE NOT EXISTS (SELECT 1 FROM clean.sellers s WHERE s.seller_id = i.seller_id))
        AS items_without_seller,

    (SELECT COUNT(*) FROM clean.order_reviews r
     WHERE NOT EXISTS (SELECT 1 FROM clean.orders o WHERE o.order_id = r.order_id))
        AS reviews_without_order;
