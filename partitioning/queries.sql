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

-- 10. Create list partition
CREATE TABLE orders_by_region (
    id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    region VARCHAR(30) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL
) PARTITION BY LIST (region);

-- 11. Create partition
CREATE TABLE orders_india
    PARTITION OF orders_by_region
    FOR VALUES IN ('India');

CREATE TABLE orders_germany
    PARTITION OF orders_by_region
    FOR VALUES IN ('Germany');

CREATE TABLE orders_usa
    PARTITION OF orders_by_region
    FOR VALUES IN ('United States');


-- 12. Insert into orders_by_region
INSERT INTO orders_by_region
VALUES (1, 100, 'India', 2500);


-- 13. Fetch Data from orders_india
SELECT * FROM orders_india;


-- 14. Create hash partitions
CREATE TABLE orders_by_hash (
    id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL
) PARTITION BY HASH (customer_id);


-- 15. Create partition
CREATE TABLE orders_hash_0
    PARTITION OF orders_by_hash
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE orders_hash_1
    PARTITION OF orders_by_hash
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

CREATE TABLE orders_hash_2
    PARTITION OF orders_by_hash
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);

CREATE TABLE orders_hash_3
    PARTITION OF orders_by_hash
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);


-- 16. Create default partition 
CREATE TABLE orders_other
    PARTITION OF orders_by_region
    DEFAULT;
CREATE TABLE
