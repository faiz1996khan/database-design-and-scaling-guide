-- 1. Create partitioned table
DROP TABLE IF EXISTS orders_partitioned CASCADE;

CREATE TABLE orders_partitioned (
    id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);


-- 2. Create partitions
CREATE TABLE orders_partitioned_2025_q3
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-07-01') TO ('2025-10-01');

CREATE TABLE orders_partitioned_2025_q4
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-10-01') TO ('2026-01-01');

CREATE TABLE orders_partitioned_2026_q1
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-04-01');

CREATE TABLE orders_partitioned_2026_q2
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-04-01') TO ('2026-07-01');

CREATE TABLE orders_partitioned_2026_q3
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2026-07-01') TO ('2026-10-01');


-- 3. Copy existing orders
INSERT INTO orders_partitioned (
    id,
    customer_id,
    order_status,
    total_amount,
    created_at
)
SELECT
    id,
    customer_id,
    order_status,
    total_amount,
    created_at
FROM orders;


-- 4. Check partition distribution
SELECT
    tableoid::regclass AS partition,
    COUNT(*)
FROM orders_partitioned
GROUP BY tableoid
ORDER BY partition;


-- 5. Demonstrate partition pruning
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM orders_partitioned
WHERE created_at >= '2026-07-01'
  AND created_at < '2026-10-01';



-- 6. Query without partition key
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM orders_partitioned;



-- 7. Add index
CREATE INDEX idx_orders_partitioned_customer
ON orders_partitioned(customer_id);


-- 8. Check partition indexes
SELECT
    tablename,
    indexname
FROM pg_indexes
WHERE tablename LIKE 'orders_partitioned%';


-- 9. Demonstrate pruning + indexing
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM orders_partitioned
WHERE created_at >= '2026-07-01'
  AND created_at < '2026-10-01'
  AND customer_id = 5000;
