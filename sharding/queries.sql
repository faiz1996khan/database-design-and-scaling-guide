-- 1. create table shard1
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 2. create index on shard1
CREATE INDEX idx_orders_customer_id
ON orders(customer_id);


-- 3. Insert data in shard1
INSERT INTO orders (
    id,
    customer_id,
    order_status,
    total_amount,
    created_at
)
SELECT
    id,
    1 + floor(random() * 50000)::BIGINT AS customer_id,
    CASE
        WHEN random() < 0.5 THEN 'pending'
        WHEN random() < 0.8 THEN 'completed'
        ELSE 'cancelled'
    END AS order_status,
    ROUND((random() * 1000)::numeric, 2),
    NOW() - (random() * INTERVAL '365 days')
FROM generate_series(1, 500000) AS id;


-- 4. Update customer ids
UPDATE orders
SET customer_id = 1 + floor(random() * 50000)::BIGINT;

-- 55. Querying shard1
SELECT *
FROM orders
WHERE customer_id = 25000
LIMIT 10;