
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
SELECT *
FROM orders
WHERE customer_id = 5000;
```

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

Run the same query using `EXPLAIN ANALYZE`.

The query may now use a Bitmap Index Scan or another index-based access method.

### 3. Index on a Low-Selectivity Column

Create an index on `order_status`.

```sql
CREATE INDEX idx_orders_status
ON orders(order_status);
```

Because many rows share the same status, PostgreSQL may still decide that scanning the table is more efficient for some queries.

**Important:** An index does not guarantee better performance for every query.

### 4. Composite Index

Create an index on both `customer_id` and `order_status`.

```sql
CREATE INDEX idx_orders_customer_status
ON orders(customer_id, order_status);
```

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
6. `EXPLAIN (ANALYZE, BUFFERS)` helps investigate query execution.
7. Index design should be based on real query patterns.