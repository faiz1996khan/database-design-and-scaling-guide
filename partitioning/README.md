# Partitioning

This section demonstrates PostgreSQL table partitioning using the `orders` dataset.

## Goal

Learn:

- What table partitioning is
- Range partitioning
- Partition pruning
- How partitioning works together with indexes

## 1. What is partitioning?

Partitioning splits one logical table into multiple smaller physical tables called **partitions**.

Example:

```text
orders_partitioned
 2025 Q3
 2025 Q4
 2026 Q1
 2026 Q2
 2026 Q3
```

Applications still query `orders_partitioned` as one table. PostgreSQL decides which partitions need to be accessed.

## 2. Why partition?

Partitioning is useful when a table becomes very large and the data has a natural distribution key such as:

- date/time
- tenant/customer ranges
- geographic regions
- status or lifecycle boundaries in selected designs

For this lab we partition by `created_at` because orders naturally have a time dimension.

## 3. Range partitioning

Our parent table is defined as:

```sql
PARTITION BY RANGE (created_at)
```

Each partition owns a range of dates.

For example:

```text
2026-07-01 → 2026-10-01
```

means that partition contains rows where:

```text
created_at >= '2026-07-01'
AND created_at <  '2026-10-01'
```
# Create order_paritioned table

<img width="576" height="203" alt="image" src="https://github.com/user-attachments/assets/acf60be3-18f9-491b-b818-e01d775113c9" />


# Create partitions based on date ranges

<img width="460" height="407" alt="image" src="https://github.com/user-attachments/assets/9ddd4466-1427-439d-a525-6df4533b856a" />


# Insert data into order_partitioned table

<img width="693" height="172" alt="image" src="https://github.com/user-attachments/assets/abb9c125-9720-4d6d-96f7-5f8024200367" />

# View paritions and number of records

<img width="442" height="241" alt="image" src="https://github.com/user-attachments/assets/c4fea7dc-6174-49fc-9a30-8ee18dda92eb" />


## 4. Partition pruning

The biggest concept is **partition pruning**.

When PostgreSQL receives a query such as:

```sql
SELECT COUNT(*)
FROM orders_partitioned
WHERE created_at >= '2026-07-01'
  AND created_at < '2026-10-01';
```

PostgreSQL can determine that only the 2026 Q3 partition can contain matching rows.

Without a partition-key condition, PostgreSQL may need to access all relevant partitions:

```sql
SELECT COUNT(*)
FROM orders_partitioned;
```

## 5. Partitioning + indexing

Partitioning and indexing solve different problems.

# Index -> Reduce the rows that need to be searched inside a table/partition
# Partitioning -> Reduce the partitions that need to be accessed
# Both -> Prune partitions first, then use indexes within the selected partitions

# Create index on customer_id 

<img width="616" height="398" alt="image" src="https://github.com/user-attachments/assets/202632ef-861e-4679-93aa-de1edbfbe17e" />

# Query on index

<img width="614" height="102" alt="image" src="https://github.com/user-attachments/assets/024a0412-522c-4a48-80ed-248f252334e2" />


<img width="981" height="335" alt="image" src="https://github.com/user-attachments/assets/b6bf0f9a-47fe-4d85-9554-825d8a8603f9" />


For example:

```sql
SELECT *
FROM orders_partitioned
WHERE created_at >= '2026-07-01'
  AND created_at < '2026-10-01'
  AND customer_id = 5000;
```

**Important:** partitioning does not replace indexes.

## 6. Partition maintenance

Partitioning can make lifecycle operations easier.

For example, if old data is stored in an old partition, that partition can be removed as a unit instead of deleting millions of rows individually.

Example:

```sql
DROP TABLE orders_partitioned_2025_q3;
```

This is a common pattern for time-based retention, although production systems should also consider backups, foreign keys, dependencies, and retention requirements before dropping data.

## 8. Important PostgreSQL detail

The example primary key is:

```sql
PRIMARY KEY (id, created_at)
```

The partition key is included because PostgreSQL's partitioned-table uniqueness rules require a unique/primary-key constraint to include the partition key.

For a production schema, choose the key strategy based on the application's actual uniqueness and lookup requirements.

## 9. What we demonstrated

- A parent table can be partitioned by range.
- Rows are automatically routed into the correct partition on insert.
- Queries containing the partition key can benefit from partition pruning.
- Indexes can exist on partitioned tables and be used within partitions.
- Partitioning helps with very large tables and lifecycle/retention operations.
