
# Database Scaling: Indexing

This section demonstrates how database indexes improve query performance and the trade-offs involved in using them.

## Objectives

- Understand how database indexes work
- Compare sequential scans and index scans
- Understand B-tree indexes
- Create single-column and composite indexes
- Understand the leftmost-prefix rule
- Analyze index size and usage
- Understand index-only scans at a high level

## Technology

- PostgreSQL 17
- Docker Compose
- SQL
- PostgreSQL EXPLAIN ANALYZE

## Dataset

We use an `orders` table containing approximately 1 million records.


id | Unique order identifier
customer_id | Customer who placed the order
order_status | pending, completed, or cancelled
total_amount | Order amount
created_at | Order creation timestamp

Records are generated using PostgreSQL's `generate_series()` function.

## What Is an Index?

An index is a separate data structure that helps the database locate rows without scanning the entire table.

Without an appropriate index, PostgreSQL may perform a sequential scan:

1. Read table pages
2. Check each row
3. Return matching rows

With an index, PostgreSQL can locate matching rows more efficiently.

However, indexes also have costs:

- Additional disk space
- Slower INSERT, UPDATE, and DELETE operations
- Additional maintenance
- The optimizer may decide that an index is not beneficial

### 1. Sequential Scan

Query orders by customer ID without an index.

```sql
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE customer_id = 5000;
```

<img width="849" height="263" alt="image" src="https://github.com/user-attachments/assets/e2d76a52-1e93-4adc-b603-ce0217735a6a" />



Expected behavior:

- PostgreSQL may scan the entire table
- More rows and pages may need to be examined
- Performance depends on table size and data distribution

### 2. Single-Column Index

Create an index on `customer_id`.

```sql
CREATE INDEX idx_orders_customer_id
ON orders(customer_id);
```

<img width="531" height="55" alt="image" src="https://github.com/user-attachments/assets/4f4b0b37-23b5-464f-9eea-11f43f6714ed" />

Run the same query.

<img width="950" height="247" alt="image" src="https://github.com/user-attachments/assets/d7b2cd75-8d9a-4da0-aeed-f26692ea9c5c" />


### 3. Index on a Low-Selectivity Column

Query orders by order_status without an index.

<img width="859" height="215" alt="image" src="https://github.com/user-attachments/assets/64e7978d-950f-4715-ab4a-bdabd5079706" />


Create an index on `order_status`.

```sql
CREATE INDEX idx_orders_status
ON orders(order_status);
```

<img width="381" height="53" alt="image" src="https://github.com/user-attachments/assets/b01c4ab5-1602-479b-b7f3-29d1d69f7fdc" />

Run the same query.

<img width="965" height="248" alt="image" src="https://github.com/user-attachments/assets/7c24a70e-c7b3-4f88-9e23-ee5425037fdf" />

Because many rows share the same status, PostgreSQL may still decide that scanning the table is more efficient for some queries.

**Important:** An index does not guarantee better performance for every query.

### 4. Composite Index

Query orders with customer_id and order_status without an index.

<img width="923" height="294" alt="image" src="https://github.com/user-attachments/assets/c3473f98-a7bb-42e0-a6d4-cff8cac2f096" />

Create an index on both `customer_id` and `order_status`.

```sql
CREATE INDEX idx_orders_customer_status
ON orders(customer_id, order_status);
```
<img width="382" height="52" alt="image" src="https://github.com/user-attachments/assets/8ac6ebbf-8026-422f-9454-825765d5f03d" />

Run the same query.

<img width="951" height="264" alt="image" src="https://github.com/user-attachments/assets/360cfc9f-55d6-47c0-b37b-c0b65445205a" />

Not a big difference here because there already exist a index on customer_id and order_status.

This index is useful for queries filtering by:

- `customer_id`
- `customer_id` and `order_status`

The column order matters.

### 5. Leftmost-Prefix Rule

For this index:

```sql
(customer_id, order_status)
```

The index can efficiently support:

```sql
WHERE customer_id = 5000
```

and:

```sql
WHERE customer_id = 5000
AND order_status = 'completed'
```

It is generally not equivalent to an index beginning with `order_status` for:

```sql
WHERE order_status = 'completed'
```

A separate status index may be useful.

## Important Observations

### Indexes are not free

Indexes consume storage and must be updated when table data changes.

### Selectivity matters

An index is usually more useful when a condition filters out a significant portion of the table.

### Composite index order matters

The order of columns should reflect common query patterns.

### The query planner decides

PostgreSQL chooses an execution plan based on statistics, estimated costs, table size, and available indexes.

### Execution time varies

Query timings depend on:

- Hardware
- Cache state
- Database statistics
- Concurrent activity
- PostgreSQL configuration

Use execution plans to understand behavior instead of relying only on one timing measurement.


## Key Takeaways

1. Indexes can reduce the amount of data PostgreSQL needs to scan.
2. B-tree indexes are suitable for many equality and range queries.
3. Composite index column order is important.
4. Indexes increase storage and write overhead.
5. PostgreSQL may choose a sequential scan even when an index exists.
6. `EXPLAIN ANALYZE` helps investigate query execution.
7. Index design should be based on real query patterns.
