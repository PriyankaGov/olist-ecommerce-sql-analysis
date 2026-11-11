/* =====================================================================
   03_analysis.sql
   Four business questions, answered with joins, CTEs and window functions.
   Revenue definition used throughout: SUM(item price) on DELIVERED orders,
   excluding freight. State this definition in your README.

   For each query, write 2-3 sentences under it in your README:
   what you found, why it matters, what the business should do.
   ===================================================================== */
USE OlistAnalysis;
GO

/* ---------------------------------------------------------------------
   Q1. Which product categories drive the most revenue, and how do
       customers rate them?
   Only categories with 100+ orders, so average scores are reliable.
   --------------------------------------------------------------------- */
SELECT TOP 15
    p.category_en                                   AS category,
    COUNT(DISTINCT o.order_id)                      AS orders,
    SUM(oi.price)                                   AS revenue,
    CAST(100.0 * SUM(oi.price) / SUM(SUM(oi.price)) OVER () AS DECIMAL(5,2)) AS pct_of_revenue,
    CAST(AVG(CAST(r.review_score AS FLOAT)) AS DECIMAL(3,2)) AS avg_review_score,
    RANK() OVER (ORDER BY SUM(oi.price) DESC)       AS revenue_rank
FROM orders o
JOIN order_items   oi ON oi.order_id   = o.order_id
JOIN products      p  ON p.product_id  = oi.product_id
LEFT JOIN order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY p.category_en
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY revenue DESC;

/* ---------------------------------------------------------------------
   Q2. How does monthly revenue trend, and what is month-on-month growth?
   Check the first and last months: if they cover only part of the month,
   leave them out of any conclusions.
   --------------------------------------------------------------------- */
WITH monthly AS (
    SELECT DATEFROMPARTS(YEAR(o.purchase_ts), MONTH(o.purchase_ts), 1) AS month_start,
           COUNT(DISTINCT o.order_id) AS orders,
           SUM(oi.price)              AS revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATEFROMPARTS(YEAR(o.purchase_ts), MONTH(o.purchase_ts), 1)
)
SELECT month_start, orders, revenue,
       LAG(revenue) OVER (ORDER BY month_start) AS prev_month_revenue,
       CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
            / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0) AS DECIMAL(12,1)) AS mom_growth_pct,
       SUM(revenue) OVER (ORDER BY month_start ROWS UNBOUNDED PRECEDING) AS running_total
FROM monthly
ORDER BY month_start;

/* ---------------------------------------------------------------------
   Q3. What share of customers order more than once, and do repeat
       customers spend more?
   Uses customer_unique_id (the real person), NOT customer_id.
   --------------------------------------------------------------------- */
WITH customer_summary AS (
    SELECT c.customer_unique_id,
           COUNT(DISTINCT o.order_id) AS orders,
           SUM(oi.price)              AS total_spend
    FROM customers c
    JOIN orders o       ON o.customer_id = c.customer_id
    JOIN order_items oi ON oi.order_id   = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END AS segment,
       COUNT(*)                                               AS customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS pct_of_customers,
       CAST(AVG(total_spend) AS DECIMAL(10,2))                AS avg_total_spend,
       CAST(SUM(total_spend) AS DECIMAL(14,2))                AS segment_revenue
FROM customer_summary
GROUP BY CASE WHEN orders = 1 THEN 'One-time' ELSE 'Repeat' END;

/* ---------------------------------------------------------------------
   Q4. Which customer states get the slowest and least reliable delivery,
       and does that show up in review scores?
   --------------------------------------------------------------------- */
SELECT TOP 15
    c.state,
    COUNT(*) AS delivered_orders,
    CAST(AVG(CAST(DATEDIFF(DAY, o.purchase_ts, o.delivered_customer_ts) AS FLOAT)) AS DECIMAL(5,1)) AS avg_delivery_days,
    CAST(100.0 * SUM(CASE WHEN o.delivered_customer_ts > o.estimated_delivery_ts THEN 1 ELSE 0 END)
         / COUNT(*) AS DECIMAL(5,2)) AS pct_late,
    CAST(AVG(CAST(r.review_score AS FLOAT)) AS DECIMAL(3,2)) AS avg_review_score
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
LEFT JOIN order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.delivered_customer_ts IS NOT NULL
GROUP BY c.state
HAVING COUNT(*) >= 200
ORDER BY pct_late DESC;

/* ---------------------------------------------------------------------
   Q4b. Follow-up: how much does a late delivery cost in review score?
   A clean, presentable finding for the dashboard.
   --------------------------------------------------------------------- */
SELECT CASE WHEN o.delivered_customer_ts > o.estimated_delivery_ts THEN 'Late' ELSE 'On time' END AS delivery,
       COUNT(*) AS orders,
       CAST(AVG(CAST(r.review_score AS FLOAT)) AS DECIMAL(3,2)) AS avg_review_score
FROM orders o
JOIN order_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered' AND o.delivered_customer_ts IS NOT NULL
GROUP BY CASE WHEN o.delivered_customer_ts > o.estimated_delivery_ts THEN 'Late' ELSE 'On time' END;
