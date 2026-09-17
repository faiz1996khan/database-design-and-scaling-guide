# Database Scaling - Sharding

This module demonstrates **database sharding** using multiple PostgreSQL instances with Node.js.

## 1. What Is Sharding?

Sharding splits data across multiple independent database instances.

Unlike partitioning, where data is divided inside one database, sharding distributes data across separate databases.



## 2. Why Sharding?

A single database can eventually become limited by:

* CPU and memory
* Storage
* Disk I/O
* Connection limits
* Read/write throughput

Sharding allows the workload to be distributed horizontally.
However, sharding also introduces distributed system complexity.


# 3. Docker Setup

Create 2 shard-1 and shard-2 different containers refer `docker-compose.yml`.

# 4. Create shard

create shard-1

create shard-2


# 7. What Is a Shard Key

A shard key determines where a record should live.

A good shard key should ideally provide:

* Reasonably balanced data
* Balanced traffic
* Efficient routing
* Fewer cross-shard queries

The shard key should be chosen based on the application's access patterns.


# 8. Shard Manager

Instead of putting routing logic throughout the application, we created a central shard manager.

check `shard-manager.js`

# 9. Targeted Routing

When the query contains the shard key, we can route directly to one shard.

Example:

```sql
SELECT *
FROM orders
WHERE customer_id = 25000;
```

Only one database is contacted.

This is called **targeted routing**.
It is the ideal case for a sharded database.

check `trageted-query.js`


# 10. Scatter-Gather

Some queries don't contain the shard key.

Example:

```sql
SELECT COUNT(*)
FROM orders
WHERE order_status = 'completed';
```

We don't know which shard contains all matching rows.

So the application queries multiple shards:

This is called **scatter-gather**.

We execute the queries in parallel and combine the results in the application.

check `scatter-gather.js`

# 11. Targeted vs Scatter-Gather

|                  | Targeted        | Scatter-Gather     |
| ---------------- | --------------- | ------------------ |
| Shards contacted | One             | Multiple           |
| Uses shard key   | Yes             | Usually no         |
| Latency          | Lower           | Higher             |
| Network calls    | Fewer           | More               |
| Example          | Customer orders | Global order count |

A good sharding design tries to maximize targeted queries.


# 12. Handling Shard Failure

If we use:

```javascript
Promise.all(...)
```

and one shard fails, the complete operation fails.

For operations where partial results can be handled, we can use:

```javascript
Promise.allSettled(...)
```

This lets us distinguish:

```text
Shard 1 - success
Shard 2 - failure
```

For important financial or transactional operations, incomplete data should generally not be presented as a complete result.

# 13. Shard Rebalancing

Adding another shard is not just a routing change.

Suppose we start with:

```text
Shard 1 - 1–50,000
Shard 2 - 50,001–100,000
```

and add Shard 3.

We might want:

```text
Shard 1 - 1–33,333
Shard 2 - 33,334–66,666
Shard 3 - 66,667–100,000
```

But existing data is still on the old shards.

Therefore:

Rebalancing usually involves:

1. Creating the new shard.
2. Moving/copying the required data.
3. Handling writes during migration.
4. Validating the migrated data.
5. Updating routing.
6. Removing old copies after a safe cutover.


# 14. Range vs Hash Sharding

## Range-based

Our lab uses range-based sharding:

```text
1–50,000 - Shard 1
50,001–100,000 - Shard 2
```

Simple and useful for demonstrating routing and range ownership.

The downside is that traffic can become uneven.

## Hash-based

A simple example:

```typescript
const shard = customerId % 2;
```

This distributes individual customers more evenly.
The downside is that related IDs can be spread across different shards, and range queries become harder.


# 15. Cross-Shard Transactions

The biggest complexity appears when one business operation touches multiple shards.

Example:

```text
Customer A - Shard 1
Customer B - Shard 2
```

A transaction involving both cannot be treated like a normal single-database transaction.

This introduces problems involving:

* Partial failures
* Consistency
* Retries
* Distributed transactions

A common design goal is therefore to keep strongly related operations on the same shard whenever possible.

# 16. Advantages

Sharding can provide:

* Horizontal database scaling
* Higher total storage capacity
* Increased write capacity
* Workload isolation
* Failure isolation

# 17. Disadvantages

Sharding introduces:

* Routing complexity
* Cross-shard queries
* Cross-shard transactions
* Rebalancing complexity
* More databases to monitor and maintain

# 18. What We Implemented

This demonstrates:

```text
✓ Two PostgreSQL shards
✓ Shard key: customer_id
✓ Range-based routing
✓ Shard manager
✓ Targeted queries
✓ Scatter-gather queries
✓ Parallel shard queries
✓ Shard failure handling
✓ Shard health checks
✓ Rebalancing concepts
✓ Cross-shard transaction challenges
```

The main idea is:

**Sharding distributes data and workload across independent databases, but the application now has to understand where data lives and how to coordinate operations across shards.**
