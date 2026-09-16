-- 2. SEED DATA
INSERT INTO orders (
    customer_id,
    order_status,
    total_amount,
    created_at
)
SELECT
    floor(random() * 100000 + 1)::BIGINT,
    (
        ARRAY['pending', 'completed', 'cancelled']
    )[floor(random() * 3 + 1)::INT],
    round((random() * 1000 + 10)::NUMERIC, 2),
    NOW() - (random() * INTERVAL '365 days')
FROM generate_series(1, 1000000);


-- 3. CHECK DATA
SELECT COUNT(*)
FROM orders;

SELECT *
FROM orders
LIMIT 10;



-- 4. QUERY WITHOUT CUSTOMER INDEX
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE customer_id = 5000;


-- 5. CREATE CUSTOMER ID INDEX
CREATE INDEX idx_orders_customer_id
ON orders(customer_id);


-- Run the same query again
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE customer_id = 5000;


-- 6. STATUS QUERY WITHOUT STATUS INDEX
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE order_status = 'completed';


-- 7. CREATE STATUS INDEX
CREATE INDEX idx_orders_status
ON orders(order_status);


-- Run the same query again
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE order_status = 'completed';


-- 8. QUERY USING TWO CONDITIONS
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE customer_id = 5000
  AND order_status = 'completed';


-- 9. CREATE COMPOSITE INDEX
CREATE INDEX idx_orders_customer_status
ON orders(customer_id, order_status);


-- Run the same query again
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE customer_id = 5000
  AND order_status = 'completed';



-- 10. LEFTMOST-PREFIX TEST
-- The composite index can support customer_id alone
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE customer_id = 5000;


-- Test order_status alone
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders
WHERE order_status = 'completed';


-- 11. INDEX-ONLY SCAN
-- Only columns present in the composite index
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, order_status
FROM orders
WHERE customer_id = 5000;


-- A column not included in the composite index
-- This may require accessing the table heap
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, order_status, total_amount
FROM orders
WHERE customer_id = 5000;


-- 12. LIST ALL INDEXES
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'orders';


-- 13. CHECK INDEX SIZES
SELECT
    indexrelname AS index_name,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE relname = 'orders';


-- 14. CHECK INDEX USAGE
SELECT
    indexrelname AS index_name,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY idx_scan DESC;
