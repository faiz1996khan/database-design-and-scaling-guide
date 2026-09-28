CREATE USER replicator
WITH REPLICATION
LOGIN
PASSWORD 'replicatorpassword';

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO orders (customer_id, total_amount)
VALUES
    (1001, 500.00),
    (1002, 750.00),
    (1003, 1200.00);