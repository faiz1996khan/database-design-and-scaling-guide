
INSERT INTO orders (
    customer_id,
    order_status,
    total_amount,
    created_at
)
SELECT
    (random() * 100000)::BIGINT + 1,
    (ARRAY['pending', 'completed', 'cancelled'])
        [floor(random() * 3 + 1)::INT],
    round((random() * 10000)::numeric, 2),
    NOW() - (random() * INTERVAL '365 days')
FROM generate_series(1, 1000000);