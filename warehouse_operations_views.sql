-- =========================================================
-- Smart Warehouse / Operations Command Center
-- Author: Nura Alam Shohag
-- Database: PostgreSQL
-- Description:
--   Executive-grade monthly warehouse operations view
-- =========================================================


-- =========================================================
-- 1. Monthly SKU Demand Aggregation
-- =========================================================

CREATE OR REPLACE VIEW vw_warehouse_operations_monthly AS

WITH monthly_demand AS (
    SELECT
        p.product_sku,
        p.product_name,
        DATE_TRUNC('month', c.calendar_date) AS sales_month,
        SUM(f.order_quantity) AS total_units_sold
    FROM fact_sales AS f
    JOIN dim_product AS p
        ON f.product_key = p.product_key
    JOIN calendar AS c
        ON f.order_date = c.calendar_date
    GROUP BY
        p.product_sku,
        p.product_name,
        DATE_TRUNC('month', c.calendar_date)
),


-- =========================================================
-- 2. Rolling Forecast & Volatility (3-month window)
-- =========================================================

rolling_metrics AS (
    SELECT
        product_sku,
        product_name,
        sales_month,
        total_units_sold,
        AVG(total_units_sold) OVER (
            PARTITION BY product_sku
            ORDER BY sales_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS avg_3_month_demand,
        STDDEV(total_units_sold) OVER (
            PARTITION BY product_sku
            ORDER BY sales_month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS demand_volatility
    FROM monthly_demand
),


-- =========================================================
-- 3. Demand Classification & Risk Signals
-- =========================================================

risk_signals AS (
    SELECT
        product_sku,
        product_name,
        sales_month,
        total_units_sold,
        avg_3_month_demand,
        demand_volatility,
        CASE
            WHEN total_units_sold > avg_3_month_demand * 1.2 THEN 'High Demand'
            WHEN total_units_sold < avg_3_month_demand * 0.8 THEN 'Low Demand'
            ELSE 'Stable'
        END AS demand_signal,
        CASE
            WHEN total_units_sold > (avg_3_month_demand + avg_3_month_demand * 0.5)
            THEN 1 
			ELSE 0
        END AS stockout_risk,
        CASE
            WHEN total_units_sold < avg_3_month_demand * 0.8
            THEN 1 
			ELSE 0
        END AS overstock_risk
    FROM rolling_metrics
)


-- =========================================================
-- 4. Final Executive Warehouse View
-- =========================================================

SELECT
    product_sku,
    product_name,
    sales_month,
    total_units_sold,
    avg_3_month_demand,
    demand_volatility,
    demand_signal,
    stockout_risk,
    overstock_risk,
    CASE
        WHEN stockout_risk = 1 THEN 'Reorder Immediately'
        WHEN overstock_risk = 1 THEN 'Reduce Inventory'
        ELSE 'Monitor'
    END AS recommended_action

FROM risk_signals;
