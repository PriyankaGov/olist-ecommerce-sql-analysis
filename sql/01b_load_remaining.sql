/* =====================================================================
   01b_load_remaining.sql
   Run AFTER 01_setup_and_load.sql stopped at the reviews file.
   Loads products, sellers and the category translation first, then
   retries reviews without a fixed ROWTERMINATOR.
   Safe to re-run: each staging table is emptied before loading.
   Assumes the CSVs are in C:\olist\ (edit the paths if not).
   ===================================================================== */
USE OlistAnalysis;
GO

TRUNCATE TABLE stg_products;
TRUNCATE TABLE stg_sellers;
TRUNCATE TABLE stg_category_translation;
TRUNCATE TABLE stg_order_reviews;
GO

BULK INSERT stg_products FROM 'C:\olist\olist_products_dataset.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_sellers FROM 'C:\olist\olist_sellers_dataset.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

BULK INSERT stg_category_translation FROM 'C:\olist\product_category_name_translation.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, FIELDTERMINATOR = ',',
      ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);
GO

/* Reviews: no ROWTERMINATOR, so CSV mode detects the line endings itself */
BULK INSERT stg_order_reviews FROM 'C:\olist\olist_order_reviews_dataset.csv'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIRSTROW = 2, FIELDTERMINATOR = ',',
      CODEPAGE = '65001', TABLOCK);
GO

/* ---------- Row counts ---------- */
SELECT 'stg_customers' AS tbl, COUNT(*) AS row_count FROM stg_customers UNION ALL
SELECT 'stg_orders',          COUNT(*) FROM stg_orders          UNION ALL
SELECT 'stg_order_items',     COUNT(*) FROM stg_order_items     UNION ALL
SELECT 'stg_order_payments',  COUNT(*) FROM stg_order_payments  UNION ALL
SELECT 'stg_order_reviews',   COUNT(*) FROM stg_order_reviews   UNION ALL
SELECT 'stg_products',        COUNT(*) FROM stg_products        UNION ALL
SELECT 'stg_sellers',         COUNT(*) FROM stg_sellers         UNION ALL
SELECT 'stg_category_translation', COUNT(*) FROM stg_category_translation;
