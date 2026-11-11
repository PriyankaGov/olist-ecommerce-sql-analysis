/* =====================================================================
   04_dashboard_views.sql
   Three reporting views for Power BI. They reuse the same definitions
   as 03_analysis.sql, so the dashboard matches the README:
     - Revenue = SUM(item price) on DELIVERED orders, excluding freight
     - Late = delivered after the estimated delivery date
     - Customers = customer_unique_id (the real person)
   ===================================================================== */
USE OlistAnalysis;
GO

/* One row per delivered order */
CREATE OR ALTER VIEW dbo.vw_order_facts AS
SELECT o.order_id,
       c.customer_unique_id,
       c.state,
       CAST(o.purchase_ts AS DATE) AS purchase_date,
       COALESCE(i.revenue, 0)      AS revenue,
       COALESCE(i.freight, 0)      AS freight,
       DATEDIFF(DAY, o.purchase_ts, o.delivered_customer_ts) AS delivery_days,
       CASE WHEN o.delivered_customer_ts IS NULL THEN NULL
            WHEN o.delivered_customer_ts > o.estimated_delivery_ts THEN 1
            ELSE 0 END             AS is_late,
       r.review_score
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN (SELECT order_id, SUM(price) AS revenue, SUM(freight_value) AS freight
           FROM order_items GROUP BY order_id) i ON i.order_id = o.order_id
LEFT JOIN order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';
GO

/* One row per item on a delivered order (for category analysis) */
CREATE OR ALTER VIEW dbo.vw_item_facts AS
SELECT oi.order_id,
       oi.order_item_id,
       p.category_en AS category,
       oi.price,
       CAST(o.purchase_ts AS DATE) AS purchase_date,
       c.state,
       r.review_score
FROM order_items oi
JOIN orders o     ON o.order_id    = oi.order_id
JOIN products p   ON p.product_id  = oi.product_id
JOIN customers c  ON c.customer_id = o.customer_id
LEFT JOIN order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';
GO

/* One row per real customer (for retention analysis) */
CREATE OR ALTER VIEW dbo.vw_customer_summary AS
SELECT c.customer_unique_id,
       COUNT(DISTINCT o.order_id) AS orders,
       SUM(oi.price)              AS total_spend,
       CASE WHEN COUNT(DISTINCT o.order_id) = 1 THEN 'One-time' ELSE 'Repeat' END AS segment
FROM customers c
JOIN orders o       ON o.customer_id = c.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id;
GO

/* ---------- Checks: these should match your earlier results ---------- */
SELECT SUM(revenue) AS total_revenue FROM dbo.vw_order_facts;            -- expect 13221498.11
SELECT segment, COUNT(*) AS customers FROM dbo.vw_customer_summary GROUP BY segment;  -- Repeat 2801, One-time 90557
