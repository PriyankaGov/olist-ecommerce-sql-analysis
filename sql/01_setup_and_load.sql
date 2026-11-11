/* =====================================================================
   01_setup_and_load.sql
   Creates the database and loads the raw Olist CSVs into staging tables.
   Staging = everything as text, so the import never fails on bad data.
   Cleaning and typing happens in 02_clean_and_model.sql.

   BEFORE RUNNING:
   1. Download the Olist dataset from Kaggle and unzip it.
   2. Change @path below to the folder holding the CSVs. The folder must
      be readable by the SQL Server service account (e.g. C:\olist\).
   3. Needs SQL Server 2017+ (for FORMAT = 'CSV').
   If BULK INSERT gives permission errors, use SSMS instead:
   right-click database > Tasks > Import Flat File, and load each CSV
   into the matching stg_ table as text columns.
   ===================================================================== */

IF DB_ID('OlistAnalysis') IS NULL
    CREATE DATABASE OlistAnalysis;
GO
USE OlistAnalysis;
GO

/* ---------- Staging tables (all text) ---------- */
DROP TABLE IF EXISTS stg_customers, stg_orders, stg_order_items, stg_order_payments,
                     stg_order_reviews, stg_products, stg_sellers, stg_category_translation;

CREATE TABLE stg_customers (
    customer_id NVARCHAR(100), customer_unique_id NVARCHAR(100),
    customer_zip_code_prefix NVARCHAR(20), customer_city NVARCHAR(100), customer_state NVARCHAR(10));

CREATE TABLE stg_orders (
    order_id NVARCHAR(100), customer_id NVARCHAR(100), order_status NVARCHAR(30),
    order_purchase_timestamp NVARCHAR(30), order_approved_at NVARCHAR(30),
    order_delivered_carrier_date NVARCHAR(30), order_delivered_customer_date NVARCHAR(30),
    order_estimated_delivery_date NVARCHAR(30));

CREATE TABLE stg_order_items (
    order_id NVARCHAR(100), order_item_id NVARCHAR(10), product_id NVARCHAR(100),
    seller_id NVARCHAR(100), shipping_limit_date NVARCHAR(30),
    price NVARCHAR(30), freight_value NVARCHAR(30));

CREATE TABLE stg_order_payments (
    order_id NVARCHAR(100), payment_sequential NVARCHAR(10), payment_type NVARCHAR(30),
    payment_installments NVARCHAR(10), payment_value NVARCHAR(30));

CREATE TABLE stg_order_reviews (
    review_id NVARCHAR(100), order_id NVARCHAR(100), review_score NVARCHAR(5),
    review_comment_title NVARCHAR(MAX), review_comment_message NVARCHAR(MAX),
    review_creation_date NVARCHAR(30), review_answer_timestamp NVARCHAR(30));

CREATE TABLE stg_products (
    product_id NVARCHAR(100), product_category_name NVARCHAR(100),
    product_name_lenght NVARCHAR(10), product_description_lenght NVARCHAR(10),
    product_photos_qty NVARCHAR(10), product_weight_g NVARCHAR(20),
    product_length_cm NVARCHAR(20), product_height_cm NVARCHAR(20), product_width_cm NVARCHAR(20));

CREATE TABLE stg_sellers (
    seller_id NVARCHAR(100), seller_zip_code_prefix NVARCHAR(20),
    seller_city NVARCHAR(100), seller_state NVARCHAR(10));

CREATE TABLE stg_category_translation (
    product_category_name NVARCHAR(100), product_category_name_english NVARCHAR(100));
GO

/* ---------- Bulk load ---------- */
DECLARE @path NVARCHAR(300) = N'C:\olist\';   
DECLARE @sql  NVARCHAR(MAX);

DECLARE @files TABLE (tbl SYSNAME, filename NVARCHAR(100));
INSERT INTO @files VALUES
 ('stg_customers',            'olist_customers_dataset.csv'),
 ('stg_orders',               'olist_orders_dataset.csv'),
 ('stg_order_items',          'olist_order_items_dataset.csv'),
 ('stg_order_payments',       'olist_order_payments_dataset.csv'),
 ('stg_order_reviews',        'olist_order_reviews_dataset.csv'),
 ('stg_products',             'olist_products_dataset.csv'),
 ('stg_sellers',              'olist_sellers_dataset.csv'),
 ('stg_category_translation', 'product_category_name_translation.csv');

DECLARE @tbl SYSNAME, @file NVARCHAR(100);
DECLARE c CURSOR FOR SELECT tbl, filename FROM @files;
OPEN c; FETCH NEXT FROM c INTO @tbl, @file;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'BULK INSERT ' + QUOTENAME(@tbl) + N' FROM ''' + @path + @file + N'''
        WITH (FORMAT = ''CSV'', FIELDQUOTE = ''"'', FIRSTROW = 2,
              FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'', CODEPAGE = ''65001'', TABLOCK);';
    EXEC sp_executesql @sql;
    FETCH NEXT FROM c INTO @tbl, @file;
END
CLOSE c; DEALLOCATE c;
GO

/* ---------- Sanity check: row counts ---------- */
SELECT 'stg_customers' AS tbl, COUNT(*) AS row_count FROM stg_customers UNION ALL
SELECT 'stg_orders',          COUNT(*) FROM stg_orders          UNION ALL
SELECT 'stg_order_items',     COUNT(*) FROM stg_order_items     UNION ALL
SELECT 'stg_order_payments',  COUNT(*) FROM stg_order_payments  UNION ALL
SELECT 'stg_order_reviews',   COUNT(*) FROM stg_order_reviews   UNION ALL
SELECT 'stg_products',        COUNT(*) FROM stg_products        UNION ALL
SELECT 'stg_sellers',         COUNT(*) FROM stg_sellers         UNION ALL
SELECT 'stg_category_translation', COUNT(*) FROM stg_category_translation;
