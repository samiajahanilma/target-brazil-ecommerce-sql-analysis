-- =========================================================
-- Author       : Samia Jahan Ilma
-- Project      : Target Brazil E-Commerce SQL Business Case Analysis
-- SQL Dialect  : Google BigQuery
-- Dataset      : target_ecom
-- =========================================================


-- =========================================================
-- 1. EXPLORATORY ANALYSIS
-- =========================================================

-- 1.1 Data types of all columns in the customers table
SELECT
    column_name,
    data_type
FROM target_ecom.INFORMATION_SCHEMA.COLUMNS
WHERE table_name = 'customers';


-- 1.2 Get the time range in which orders were placed
SELECT
    MIN(order_purchase_timestamp) AS first_order,
    MAX(order_purchase_timestamp) AS last_order
FROM target_ecom.orders;


-- 1.3 Count unique customer cities and states
SELECT
    COUNT(DISTINCT c.customer_city) AS no_of_unique_customer_cities,
    COUNT(DISTINCT c.customer_state) AS no_of_unique_customer_states
FROM target_ecom.customers AS c
INNER JOIN target_ecom.orders AS o
    ON c.customer_id = o.customer_id;



-- =========================================================
-- 2. IN-DEPTH EXPLORATION
-- =========================================================

-- 2.1 Is there a growing trend in the number of orders placed over the years?
SELECT
    year,
    month_numeric,
    order_count_per_month_per_year,
    SUM(order_count_per_month_per_year) OVER (
        PARTITION BY year
        ORDER BY month_numeric
    ) AS cumulative_order_count_per_year
FROM (
    SELECT
        EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
        EXTRACT(MONTH FROM order_purchase_timestamp) AS month_numeric,
        COUNT(order_id) AS order_count_per_month_per_year
    FROM target_ecom.orders
    GROUP BY year, month_numeric
) AS monthly_orders
ORDER BY year, month_numeric;


-- 2.2 Monthly seasonality in number of orders
SELECT
    year,
    month,
    order_count_per_month_per_year,
    MAX(order_count_per_month_per_year) OVER (PARTITION BY year) AS max_order_per_year,
    FIRST_VALUE(month) OVER (
        PARTITION BY year
        ORDER BY order_count_per_month_per_year DESC
    ) AS max_order_month_per_year,
    MIN(order_count_per_month_per_year) OVER (PARTITION BY year) AS min_order_per_year,
    FIRST_VALUE(month) OVER (
        PARTITION BY year
        ORDER BY order_count_per_month_per_year
    ) AS min_order_month_per_year
FROM (
    SELECT
        EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
        FORMAT_DATE('%B', DATE(order_purchase_timestamp)) AS month,
        COUNT(order_id) AS order_count_per_month_per_year
    FROM target_ecom.orders
    GROUP BY year, month
) AS monthly_seasonality
ORDER BY year, month;


-- 2.3 Time of day when customers place most orders
-- 0-6  : Dawn
-- 7-12 : Morning
-- 13-18: Afternoon
-- 19-23: Night
SELECT
    day_stage,
    order_counts,
    MAX(order_counts) OVER () AS max_order_counts,
    FIRST_VALUE(day_stage) OVER (ORDER BY order_counts DESC) AS max_order_day_stage
FROM (
    SELECT
        CASE
            WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 0 AND 6 THEN 'Dawn'
            WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 7 AND 12 THEN 'Morning'
            WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 13 AND 18 THEN 'Afternoon'
            WHEN EXTRACT(HOUR FROM order_purchase_timestamp) BETWEEN 19 AND 23 THEN 'Night'
        END AS day_stage,
        COUNT(order_id) AS order_counts
    FROM target_ecom.orders
    GROUP BY day_stage
) AS order_time_analysis
ORDER BY order_counts DESC;



-- =========================================================
-- 3. EVOLUTION OF E-COMMERCE ORDERS IN BRAZIL
-- =========================================================

-- 3.1 Month-on-month number of orders placed in each state
SELECT
    EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year,
    FORMAT_DATE('%B', DATE(o.order_purchase_timestamp)) AS month,
    c.customer_state AS state,
    COUNT(o.order_id) AS order_count
FROM target_ecom.orders AS o
INNER JOIN target_ecom.customers AS c
    ON o.customer_id = c.customer_id
GROUP BY year, month, state
ORDER BY year, month, state;


-- 3.2 Customer distribution across states
SELECT
    customer_state,
    COUNT(DISTINCT customer_id) AS unique_customer_count_per_state
FROM target_ecom.customers
GROUP BY customer_state
ORDER BY unique_customer_count_per_state DESC;



-- =========================================================
-- 4. IMPACT ON ECONOMY
-- =========================================================

-- 4.1 Percentage increase in order cost from 2017 to 2018
-- Jan to Aug only
WITH yearly_payment AS (
    SELECT
        EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year,
        ROUND(SUM(p.payment_value), 2) AS total_payment_value
    FROM target_ecom.orders AS o
    INNER JOIN target_ecom.payments AS p
        ON o.order_id = p.order_id
    WHERE EXTRACT(MONTH FROM o.order_purchase_timestamp) BETWEEN 1 AND 8
    GROUP BY year
)
SELECT
    year,
    total_payment_value,
    ROUND(
        (
            (total_payment_value - LEAD(total_payment_value) OVER (ORDER BY year DESC))
            / LEAD(total_payment_value) OVER (ORDER BY year DESC)
        ) * 100,
        2
    ) AS percentage_increase
FROM yearly_payment
ORDER BY year DESC;


-- 4.2 Total and average order value for each state
SELECT
    c.customer_state,
    ROUND(SUM(p.payment_value), 2) AS total_value_of_orders,
    ROUND(AVG(p.payment_value), 2) AS avg_value_of_orders
FROM target_ecom.customers AS c
INNER JOIN target_ecom.orders AS o
    ON c.customer_id = o.customer_id
INNER JOIN target_ecom.payments AS p
    ON o.order_id = p.order_id
GROUP BY c.customer_state
ORDER BY c.customer_state;


-- 4.3 Total and average freight value for each state
WITH order_freight AS (
    SELECT
        order_id,
        freight_value,
        COUNT(*) AS item_count
    FROM target_ecom.order_items
    GROUP BY order_id, freight_value
)
SELECT
    c.customer_state,
    ROUND(SUM(ofr.freight_value * ofr.item_count), 2) AS total_freight_value,
    ROUND(AVG(ofr.freight_value * ofr.item_count), 2) AS avg_freight_value
FROM order_freight AS ofr
INNER JOIN target_ecom.orders AS o
    ON ofr.order_id = o.order_id
INNER JOIN target_ecom.customers AS c
    ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY c.customer_state;



-- =========================================================
-- 5. ANALYSIS BASED ON SALES, FREIGHT, AND DELIVERY TIME
-- =========================================================

-- 5.1 Delivery time and difference between estimated and actual delivery date
SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    DATE_DIFF(DATE(order_delivered_customer_date), DATE(order_purchase_timestamp), DAY) AS time_to_deliver,
    DATE_DIFF(DATE(order_delivered_customer_date), DATE(order_estimated_delivery_date), DAY) AS diff_between_estimated_and_actual_delivery
FROM target_ecom.orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_status = 'delivered'
ORDER BY time_to_deliver DESC;


-- 5.2 Top 5 and bottom 5 states by average freight value
WITH order_freight AS (
    SELECT
        order_id,
        freight_value,
        COUNT(*) AS item_count
    FROM target_ecom.order_items
    GROUP BY order_id, freight_value
),
state_freight AS (
    SELECT
        c.customer_state,
        ROUND(AVG(ofr.freight_value * ofr.item_count), 2) AS avg_freight_value
    FROM order_freight AS ofr
    INNER JOIN target_ecom.orders AS o
        ON ofr.order_id = o.order_id
    INNER JOIN target_ecom.customers AS c
        ON c.customer_id = o.customer_id
    GROUP BY c.customer_state
),
top_5 AS (
    SELECT
        customer_state,
        avg_freight_value,
        ROW_NUMBER() OVER (ORDER BY avg_freight_value DESC) AS rn
    FROM state_freight
),
bottom_5 AS (
    SELECT
        customer_state,
        avg_freight_value,
        ROW_NUMBER() OVER (ORDER BY avg_freight_value ASC) AS rn
    FROM state_freight
)
SELECT
    t.customer_state AS top_5_states,
    t.avg_freight_value AS top_5_freight_values,
    b.customer_state AS bottom_5_states,
    b.avg_freight_value AS bottom_5_freight_values
FROM top_5 AS t
INNER JOIN bottom_5 AS b
    ON t.rn = b.rn
WHERE t.rn <= 5
ORDER BY t.rn;


-- 5.3 Top 5 and bottom 5 states by average delivery time
WITH state_delivery AS (
    SELECT
        c.customer_state,
        ROUND(
            AVG(
                DATE_DIFF(
                    DATE(order_delivered_customer_date),
                    DATE(order_purchase_timestamp),
                    DAY
                )
            ),
            2
        ) AS avg_delivery_time
    FROM target_ecom.orders AS o
    INNER JOIN target_ecom.customers AS c
        ON c.customer_id = o.customer_id
    WHERE order_delivered_customer_date IS NOT NULL
      AND order_status = 'delivered'
    GROUP BY c.customer_state
),
top_5 AS (
    SELECT
        customer_state,
        avg_delivery_time,
        ROW_NUMBER() OVER (ORDER BY avg_delivery_time DESC) AS rn
    FROM state_delivery
),
bottom_5 AS (
    SELECT
        customer_state,
        avg_delivery_time,
        ROW_NUMBER() OVER (ORDER BY avg_delivery_time ASC) AS rn
    FROM state_delivery
)
SELECT
    t.customer_state AS top_5_states,
    t.avg_delivery_time AS top_5_avg_delivery_time,
    b.customer_state AS bottom_5_states,
    b.avg_delivery_time AS bottom_5_avg_delivery_time
FROM top_5 AS t
INNER JOIN bottom_5 AS b
    ON t.rn = b.rn
WHERE t.rn <= 5
ORDER BY t.rn;


-- 5.4 Top 5 states with fastest delivery compared to estimated delivery date
WITH state_delivery_diff AS (
    SELECT
        c.customer_state,
        ROUND(
            AVG(
                DATE_DIFF(
                    DATE(order_delivered_customer_date),
                    DATE(order_estimated_delivery_date),
                    DAY
                )
            ),
            2
        ) AS avg_diff_between_estimated_and_actual_delivery
    FROM target_ecom.orders AS o
    INNER JOIN target_ecom.customers AS c
        ON c.customer_id = o.customer_id
    WHERE order_delivered_customer_date IS NOT NULL
      AND order_status = 'delivered'
    GROUP BY c.customer_state
)
SELECT
    customer_state AS top_5_fast_delivery_states,
    avg_diff_between_estimated_and_actual_delivery
FROM (
    SELECT
        customer_state,
        avg_diff_between_estimated_and_actual_delivery,
        ROW_NUMBER() OVER (
            ORDER BY avg_diff_between_estimated_and_actual_delivery ASC
        ) AS rn
    FROM state_delivery_diff
    WHERE avg_diff_between_estimated_and_actual_delivery < 0
) AS ranked_states
WHERE rn <= 5
ORDER BY avg_diff_between_estimated_and_actual_delivery;


-- 5.5 Freight cost summary by state
WITH order_freight AS (
    SELECT
        order_id,
        freight_value,
        COUNT(*) AS item_count
    FROM target_ecom.order_items
    GROUP BY order_id, freight_value
)
SELECT
    c.customer_state,
    COUNT(o.order_id) AS order_count,
    ROUND(SUM(ofr.freight_value * ofr.item_count), 2) AS total_freight_value,
    ROUND(AVG(ofr.freight_value * ofr.item_count), 2) AS avg_freight_value
FROM order_freight AS ofr
INNER JOIN target_ecom.orders AS o
    ON ofr.order_id = o.order_id
INNER JOIN target_ecom.customers AS c
    ON c.customer_id = o.customer_id
GROUP BY c.customer_state
ORDER BY total_freight_value DESC;



-- =========================================================
-- 6. ANALYSIS BASED ON PAYMENTS
-- =========================================================

-- 6.1 Month-on-month number of orders placed using different payment types
SELECT
    EXTRACT(YEAR FROM o.order_purchase_timestamp) AS year,
    FORMAT_DATE('%B', DATE(o.order_purchase_timestamp)) AS month,
    p.payment_type,
    COUNT(o.order_id) AS order_count
FROM target_ecom.orders AS o
INNER JOIN target_ecom.payments AS p
    ON o.order_id = p.order_id
GROUP BY year, month, p.payment_type
ORDER BY p.payment_type, year, month;


-- 6.2 Number of orders by payment installments
SELECT
    payment_installments,
    COUNT(order_id) AS order_count
FROM target_ecom.payments
WHERE payment_installments > 0
  AND payment_value > 0
GROUP BY payment_installments
ORDER BY order_count DESC;
