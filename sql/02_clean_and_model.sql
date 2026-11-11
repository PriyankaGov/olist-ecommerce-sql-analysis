/* =====================================================================
   02_clean_and_model.sql
   Turns the text staging tables into properly typed tables with
   primary and foreign keys. Every cleaning decision is commented so
   you can copy it into the README as your "Data cleaning log".
   ===================================================================== */
USE OlistAnalysis;
GO

DROP TABLE IF EXISTS order_reviews, order_payments, order_items, orders, products, sellers, customers;
GO

/* ---------- customers ----------
   NOTE: customer_id is unique PER ORDER. The real person is
   customer_unique_id. Use customer_unique_id for any retention analysis. */
CREATE TABLE customers (
    customer_id        NVARCHAR(100) NOT NULL PRIMARY KEY,
    customer_unique_id NVARCHAR(100) NOT NULL,
    zip_code_prefix    NVARCHAR(10),
    city               NVARCHAR(100),
    state              CHAR(2)
);
INSERT INTO customers
SELECT customer_id, customer_unique_id, customer_zip_code_prefix,
       LOWER(LTRIM(RTRIM(customer_city))), UPPER(LTRIM(RTRIM(customer_state)))
FROM stg_customers;

/* ---------- sellers ---------- */
CREATE TABLE sellers (
    seller_id       NVARCHAR(100) NOT NULL PRIMARY KEY,
    zip_code_prefix NVARCHAR(10),
    city            NVARCHAR(100),
    state           CHAR(2)
);
INSERT INTO sellers
SELECT seller_id, seller_zip_code_prefix,
       LOWER(LTRIM(RTRIM(seller_city))), UPPER(LTRIM(RTRIM(seller_state)))
FROM stg_sellers;

/* ---------- products ----------
   Decision: missing category -> 'unknown' (keeps the rows so revenue still adds up).
   Decision: category names translated from Portuguese to English where a
   translation exists; otherwise the Portuguese name is kept. */
CREATE TABLE products (
    product_id    NVARCHAR(100) NOT NULL PRIMARY KEY,
    category_pt   NVARCHAR(100),
    category_en   NVARCHAR(100) NOT NULL,
    weight_g      INT,
    photos_qty    INT
);
INSERT INTO products
SELECT p.product_id,
       NULLIF(p.product_category_name, ''),
       COALESCE(t.product_category_name_english, NULLIF(p.product_category_name, ''), 'unknown'),
       TRY_CAST(p.product_weight_g AS INT),
       TRY_CAST(p.product_photos_qty AS INT)
FROM stg_products p
LEFT JOIN stg_category_translation t ON t.product_category_name = p.product_category_name;

/* ---------- orders ----------
   Dates cast with TRY_CAST so blanks become NULL instead of errors.
   Undelivered/cancelled orders legitimately have NULL delivery dates. */
CREATE TABLE orders (
    order_id              NVARCHAR(100) NOT NULL PRIMARY KEY,
    customer_id           NVARCHAR(100) NOT NULL REFERENCES customers(customer_id),
    order_status          NVARCHAR(30)  NOT NULL,
    purchase_ts           DATETIME2,
    approved_ts           DATETIME2,
    delivered_carrier_ts  DATETIME2,
    delivered_customer_ts DATETIME2,
    estimated_delivery_ts DATETIME2
);
INSERT INTO orders
SELECT order_id, customer_id, order_status,
       TRY_CAST(order_purchase_timestamp       AS DATETIME2),
       TRY_CAST(order_approved_at              AS DATETIME2),
       TRY_CAST(order_delivered_carrier_date   AS DATETIME2),
       TRY_CAST(order_delivered_customer_date  AS DATETIME2),
       TRY_CAST(order_estimated_delivery_date  AS DATETIME2)
FROM stg_orders;

/* ---------- order_items ---------- */
CREATE TABLE order_items (
    order_id      NVARCHAR(100) NOT NULL REFERENCES orders(order_id),
    order_item_id INT           NOT NULL,
    product_id    NVARCHAR(100) NOT NULL REFERENCES products(product_id),
    seller_id     NVARCHAR(100) NOT NULL REFERENCES sellers(seller_id),
    price         DECIMAL(10,2) NOT NULL,
    freight_value DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);
INSERT INTO order_items
SELECT order_id, TRY_CAST(order_item_id AS INT), product_id, seller_id,
       TRY_CAST(price AS DECIMAL(10,2)), TRY_CAST(freight_value AS DECIMAL(10,2))
FROM stg_order_items;

/* ---------- order_payments ---------- */
CREATE TABLE order_payments (
    order_id           NVARCHAR(100) NOT NULL REFERENCES orders(order_id),
    payment_sequential INT           NOT NULL,
    payment_type       NVARCHAR(30)  NOT NULL,
    installments       INT,
    payment_value      DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
);
INSERT INTO order_payments
SELECT order_id, TRY_CAST(payment_sequential AS INT), payment_type,
       TRY_CAST(payment_installments AS INT), TRY_CAST(payment_value AS DECIMAL(10,2))
FROM stg_order_payments;

/* ---------- order_reviews ----------
   Decision: the raw data has duplicate review_ids and some orders with
   several reviews. Keep ONE review per order (the most recent) so joins
   don't multiply rows and inflate revenue. Comment text is dropped; this
   project is about scores. */
CREATE TABLE order_reviews (
    order_id       NVARCHAR(100) NOT NULL PRIMARY KEY REFERENCES orders(order_id),
    review_score   TINYINT       NOT NULL CHECK (review_score BETWEEN 1 AND 5),
    review_created DATETIME2
);
WITH ranked AS (
    SELECT order_id,
           TRY_CAST(review_score AS TINYINT) AS review_score,
           TRY_CAST(review_creation_date AS DATETIME2) AS review_created,
           ROW_NUMBER() OVER (PARTITION BY order_id
                              ORDER BY TRY_CAST(review_answer_timestamp AS DATETIME2) DESC) AS rn
    FROM stg_order_reviews
    WHERE TRY_CAST(review_score AS TINYINT) BETWEEN 1 AND 5
)
INSERT INTO order_reviews
SELECT order_id, review_score, review_created
FROM ranked
WHERE rn = 1
  AND order_id IN (SELECT order_id FROM orders);
GO

/* ---------- Data quality checks (screenshot these for the README) ---------- */
SELECT 'orders with no items'       AS check_name, COUNT(*) AS n
FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
UNION ALL
SELECT 'delivered orders missing delivery date', COUNT(*)
FROM orders WHERE order_status = 'delivered' AND delivered_customer_ts IS NULL
UNION ALL
SELECT 'products with unknown category', COUNT(*) FROM products WHERE category_en = 'unknown'
UNION ALL
SELECT 'orders without a review', COUNT(*)
FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_reviews r WHERE r.order_id = o.order_id);




SELECT o.order_status, COUNT(*) AS orders
  FROM orders o
  WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
  GROUP BY o.order_status
  ORDER BY orders DESC;