# Database Replication

This section demonstrates PostgreSQL database replication using Docker and PostgreSQL 17.

The goal is to understand replication practically rather than only theoretically.

We cover:

* Primary / replica architecture
* PostgreSQL WAL
* Streaming replication
* Asynchronous replication
* Initial base backup
* Read scaling
* Read-after-write consistency
* Replication lag
* Replica failure
* Primary failure
* Manual failover
* Replica promotion
* Rejoining an old primary
* Synchronous replication concepts
* Split-brain
* Logical replication
* Multi-primary / bidirectional replication
* Conflict handling


---

# 1. What Is Database Replication?

Database replication means maintaining a copy of database data on another database server.

With a primary/replica architecture:

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/833e6b7e-5428-4940-bd47-204f39de6e92" />


The primary accepts writes.

The replica receives changes from the primary and replays them.

A typical application architecture is:

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/a834b7b6-b2e9-4ec7-8c4d-d6b4affd8389" />


Replication is different from sharding.

### Replication

Every database contains the same dataset:

```text
Primary  ->  full dataset
Replica  -> full dataset
```

### Sharding

Each database contains part of the dataset:

```text
Shard 1 -> customers 1–50,000
Shard 2 -> customers 50,001–100,000
```

Replication primarily helps with:

* Read scaling
* High availability
* Failover
* Disaster recovery

Replication does not by itself solve:

* Write scaling across many machines
* A dataset that is too large for one server
* Cross-database transactions

---

We intentionally use the standard PostgreSQL Docker image.

There is no custom Dockerfile.

---

# 3. Primary / Replica

The first replication model is:

The primary is writable.

The replica is read-only while it is acting as a standby.

---

# 4. Docker Configuration

refer docker-compose.yml file

# 5. Why These PostgreSQL Settings Are Needed

The primary uses:

```text
wal_level=replica
```

This configures PostgreSQL to generate the WAL information required for physical replication.

We also configured:

```text
max_wal_senders=10
```

This controls how many WAL sender processes PostgreSQL can use to send WAL data to replication clients.

We deliberately keep this small for the learning project.

---

# 6. Configure PostgreSQL Authentication

`primary/pg_hba.conf`:

```conf
local   all             all                             trust
host    all             all             0.0.0.0/0       scram-sha-256
host    replication     repluser        0.0.0.0/0       scram-sha-256
```

The important rule is:

```conf
host replication repluser 0.0.0.0/0 scram-sha-256
```

It allows the replica to establish a replication connection to the primary.

This configuration is intentionally permissive for a local Docker lab.

A production configuration should restrict access to trusted networks or specific hosts.

---

# 7. Create the Initial Database

`primary/init.sql`:

```sql
ALTER ROLE repluser WITH REPLICATION;

CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

INSERT INTO orders (
    customer_id,
    order_status,
    total_amount
)
VALUES
    (1001, 'completed', 500.00),
    (1002, 'pending', 750.00),
    (1003, 'completed', 1200.00);
```

The `REPLICATION` attribute allows `repluser` to be used for the replication connection.

---

# 8. Important Docker Initialization Detail

PostgreSQL Docker initialization scripts execute when a PostgreSQL data directory is initialized.

Therefore, when changing:

```text
init.sql
```

you may need to remove the existing volume to initialize the database again.

For this lab:

```bash
docker compose down -v
```

Then:

```bash
docker compose up -d
```

The `-v` is important because it removes the existing Docker volumes.

Do not casually use this in production because it destroys the database volume.

---

# 9. Start the Replication

From the repository root:

```bash
docker compose up -d
```

Check:

```bash
docker ps
```

Expected containers:

```text
scaling-primary
scaling-replica
```

---

# 10. Verify the Primary

Connect to the primary:

```bash
docker exec -it scaling-primary \
psql -U repluser -d replication_primary
```

Run:

```sql
SELECT * FROM orders;
```

<img width="666" height="136" alt="image" src="https://github.com/user-attachments/assets/61ad9fdc-c62f-48ed-b090-9f9e0f655e60" />


# 11. Verify the Replica

Connect to the replica:

```bash
docker exec -it scaling-replica \
psql -U repluser -d replication_primary
```

Run:

```sql
SELECT * FROM orders;
```
<img width="520" height="141" alt="image" src="https://github.com/user-attachments/assets/21ccaec6-3faa-4586-81d6-e48ebb13dca5" />


The same rows should be present.

The flow is:

<img width="1024" height="559" alt="image" src="https://github.com/user-attachments/assets/5be61503-574e-4c75-839d-4359465c609c" />


This gives the replica an initial copy of the primary data.

---

# 12. Why `pg_basebackup` Is Required

A new replica cannot simply start with an empty PostgreSQL database and begin replaying changes.

The replica needs an initial copy.

We use:

```bash
pg_basebackup \
  -h scaling-primary \
  -p 5432 \
  -U repluser \
  -D "$PGDATA" \
  -Fp \
  -Xs \
  -P \
  -R
```

Important options:

### `-D`

Destination directory.

### `-Fp`

Plain directory format.

### `-Xs`

Include WAL required during the backup.

### `-P`

Show progress.

### `-R`

Automatically configure the copied server as a standby.

This is what allows the replica to start streaming from the primary.

---

# 13. Verify That PostgreSQL Thinks the Replica Is a Standby

On the replica:

```sql
SELECT pg_is_in_recovery();
```
<img width="529" height="101" alt="image" src="https://github.com/user-attachments/assets/0d3deb92-b71c-4c19-b1ad-cf2390dfe931" />

Meaning:

```text
t = PostgreSQL is running in recovery/standby mode
```

While acting as a physical standby, normal writes are not allowed.

---

# 14. Verify Replication From the Primary

Run on the primary:

```sql
SELECT
    client_addr,
    state,
    sync_state
FROM pg_stat_replication;
```

A healthy streaming replica should show something conceptually similar to:

<img width="443" height="159" alt="image" src="https://github.com/user-attachments/assets/d60d9ee4-8e43-4d2d-8925-edc526daea74" />


This verifies that the replica has established a streaming replication connection.

---

# 15. How Streaming Replication Works

PostgreSQL uses the Write-Ahead Log (WAL).

Instead of repeatedly copying the whole database, PostgreSQL records database changes in WAL.

<img width="235" height="408" alt="image" src="https://github.com/user-attachments/assets/500991a8-c6a7-41e4-be6c-54ef05899965" />


# 16. Test a New Write

On the primary:

```sql
INSERT INTO orders (
    customer_id,
    order_status,
    total_amount
)
VALUES (
    1004,
    'completed',
    900.00
);
```

Check primary:

```sql
SELECT * FROM orders
ORDER BY id;
```

<img width="636" height="207" alt="image" src="https://github.com/user-attachments/assets/0a0f8c68-2897-4c06-838a-2c6e7d494f44" />


Then check the replica:

```sql
SELECT * FROM orders
ORDER BY id;
```

<img width="543" height="173" alt="image" src="https://github.com/user-attachments/assets/438fce12-733a-4961-9134-552b771c9c05" />


The new order should eventually appear on the replica.

The application does not directly perform the second insert.

---

# 17. Replica Is Read-Only

Try this on the replica:

```sql
INSERT INTO orders (
    customer_id,
    order_status,
    total_amount
)
VALUES (
    2000,
    'pending',
    500.00
);
```

The standby should reject the write.

<img width="674" height="40" alt="image" src="https://github.com/user-attachments/assets/c3ae0971-86d7-4412-b3e0-5ec07fca42a0" />


This allows read traffic to be distributed across replicas.

---

# 18. Read Scaling

With replicas:

<img width="630" height="407" alt="image" src="https://github.com/user-attachments/assets/722fcf63-7594-4534-99b6-28144184c31f" />


The write workload still reaches the primary.

Read traffic can be distributed among replicas.

---

# 19. Replication Lag

Replication is not necessarily instantaneous.

With asynchronous replication:

```text
T0
Application writes to primary

T0 + small delay
Replica receives/replays the change
```

During that small period:

```text
Primary → newest state
Replica → slightly older state
```

This difference is called:

# Replication Lag

The replica may be behind the primary because of:

* Network delay
* Disk performance
* High write volume
* CPU pressure
* Long-running queries
* Replica resource limitations
* Temporary connection problems

---

# 20. Measuring Replication Progress

On the primary:

```sql
SELECT
    application_name,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

You can also inspect the WAL distance:

```sql
SELECT
    application_name,
    pg_size_pretty(
        pg_wal_lsn_diff(
            pg_current_wal_lsn(),
            replay_lsn
        )
    ) AS replay_lag
FROM pg_stat_replication;
```

If the difference grows continuously, the replica is falling behind.

---

# 21. Read-After-Write Consistency Problem

Consider:

```text
POST /orders
```

The application writes to the primary.

Immediately afterward:

```text
GET /orders
```

If the GET is routed to a replica, the new order may not yet be visible.

This creates a read-after-write consistency issue.

A common application strategy is:

Normal read from read replica
Immediate read after a write from primary

The exact approach depends on the application's consistency requirements.

---

# 22. What Happens If the Replica Fails?

Stop it:

```bash
docker stop scaling-replica
```

The primary can continue accepting writes.

For example:

```sql
INSERT INTO orders (
    customer_id,
    order_status,
    total_amount
)
VALUES (
    5000,
    'completed',
    1500.00
);
```

The transaction can still commit on the primary.

The replica is temporarily unavailable.

Start it again:

```bash
docker start scaling-replica
```

The replica can catch up using the WAL it still needs, assuming the required WAL is available.

---

# 23. What Happens If the Primary Fails?

Simulate a primary failure:

```bash
docker kill scaling-primary
```

The replica remains alive.

However, it is still a standby.

Check:

```sql
SELECT pg_is_in_recovery();
```

It should still return:

```text
t
```

Therefore:
Primary - down
Replica - still read-only


Replication alone did not automatically fail over.

---

# 24. Promote the Replica

Promote the replica:

```bash
docker exec scaling-replica \
pg_ctl promote -D /var/lib/postgresql/data
```

Verify:

```bash
docker exec -it scaling-replica \
psql -U repluser -d replication_primary \
-c "SELECT pg_is_in_recovery();"
```

Expected:

```text
f
```

<img width="878" height="226" alt="image" src="https://github.com/user-attachments/assets/3f903b6d-1fc8-48be-aacb-59f0723bb724" />


The server is no longer in standby mode.

It is now writable.

---

# 25. Verify the New Primary

Insert a new row:

```sql
INSERT INTO orders (
    customer_id,
    order_status,
    total_amount
)
VALUES (
    2000,
    'pending',
    500.00
);
```

Then:

```sql
SELECT *
FROM orders ORDER BY id;
```

<img width="650" height="266" alt="image" src="https://github.com/user-attachments/assets/a1fecb00-e454-453f-9e30-002939af9e09" />

The old replica has now become the new primary.

# 26. Promotion Is Not the Same as Automatic Failover

The promotion command was manual:

```bash
pg_ctl promote
```

A production HA system typically adds an orchestration/failover layer or uses a managed PostgreSQL service.

# 27. What Happens When the Old Primary Comes Back?

This is critical.

Suppose:
Old Primary - offline or down
New Primary - accepts new writes

The old primary is now potentially out of date.

It should not simply be considered a healthy replica and immediately put back into service.

The old primary may contain a different transaction history.

The old primary needs to be rebuilt/rejoined as a standby of the new primary.

This is known as re-provisioning or rejoining the old primary.

---

# 28. Asynchronous Replication and Possible Data Loss

Our primary/replica lab uses:

```text
sync_state = async
```

The primary doesn't wait for the replica to replay every change before acknowledging the transaction.

Therefore asynchronous replication can potentially lose the most recent transactions that had not reached the replica.

This is the main durability tradeoff of asynchronous replication.

---

# 29. RPO

RPO means:

# Recovery Point Objective

It answers:

> How much recently committed data could potentially be lost after a failure?

With asynchronous replication:
Potentially some recent transactions


With properly configured synchronous replication:
Much stronger protection against losing acknowledged transactions


There are still important operational nuances, but the tradeoff is the key concept.

---

# 30. Synchronous Replication

PostgreSQL also supports synchronous replication.

The synchronous model can provide stronger durability guarantees, but it introduces additional latency and can make the primary more dependent on replica availability.

### Tradeoff

| Async                                               | Sync                                    |
| --------------------------------------------------- | --------------------------------------- |
| Lower write latency                                 | Higher write latency                    |
| Replica may lag                                     | Stronger synchronization                |
| Potential recent-data loss                          | Lower risk of losing acknowledged data  |
| Better write availability if replica is unavailable | Replica availability can affect commits |

We discussed synchronous replication as part of the replication design, but this repository's hands-on primary/replica Docker lab uses asynchronous replication.

---

# 32. Split-Brain

One of the most dangerous distributed database problems is split-brain.

Imagine the primary becomes unreachable from the application or monitoring system, but is still running.

Another server gets promoted

Now both sides can accept writes.

The result can be conflicting database histories.

This is why production failover systems need mechanisms to ensure that only one server is allowed to act as the active primary.

This can involve:

* Leader election
* Fencing
* Quorum
* External coordination
* Managed HA services

---

# 33. Multi-Primary Replication

The second replication model in this project is bidirectional logical replication.

Instead of:

```text
Primary -> Replica
```

we configure:

```text
Node A <-----> Node B
```

Both nodes are writable.

This is commonly described as:

* Multi-primary
* Multi-master
* Bidirectional replication

In this lab, PostgreSQL logical replication is used to demonstrate the mechanics.

---

# 34. Why Logical Replication?

Physical replication is used for the primary/standby model.

Logical replication works at the logical change level.


This gives us the ability to build:

```text
A publishes -> B subscribes
B publishes -> A subscribes
```

---

# 35. Multi-Primary Docker Services

We use two PostgreSQL 17 containers.

refer replication/docker-compose.yml
---

# 36. Multi-Primary PostgreSQL Configuration

Logical replication requires:

```text
wal_level=logical
```

We also configure:

```text
max_wal_senders=10
max_replication_slots=10
```

because subscriptions require replication connections and slots.

---

# 37. Create the Table on Both Nodes

Logical replication does not automatically replicate arbitrary schema/DDL changes.

Therefore, create the table on both nodes.

Node A:

```sql
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE PUBLICATION node_a_publication
FOR TABLE orders;
```

Node B:

```sql
CREATE TABLE orders (
    id BIGINT PRIMARY KEY,
    customer_id BIGINT NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    total_amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE PUBLICATION node_b_publication
FOR TABLE orders;
```

---

# 38. Publication

A publication defines what a PostgreSQL node makes available to logical replication.

Example:

```sql
CREATE PUBLICATION node_a_publication
FOR TABLE orders;
```

---

# 39. Subscription

On Node B:

```sql
CREATE SUBSCRIPTION node_b_subscribes_to_a
CONNECTION 'host=postgres-multi-a port=5432 user=repluser password=replpassword dbname=multi_primary'
PUBLICATION node_a_publication
WITH (copy_data = false);
```
<img width="716" height="249" alt="image" src="https://github.com/user-attachments/assets/aa195e80-fb3d-41bd-b206-717c7226cef5" />



Then on Node A:

```sql
CREATE SUBSCRIPTION node_a_subscribes_to_b
CONNECTION 'host=postgres-multi-b port=5432 user=repluser password=replpassword dbname=multi_primary'
PUBLICATION node_b_publication
WITH (copy_data = false);
```
<img width="804" height="250" alt="image" src="https://github.com/user-attachments/assets/7577299d-a954-4b78-8456-849a3b15c297" />


Now:

```text
Node A <--------> Node B
```

---

# 40. Why `copy_data=false`?

Both databases were initialized independently.

We want to start the demonstration with empty tables and then replicate new changes.

Therefore:

```sql
WITH (copy_data = false)
```

means:

```text
Do not perform an initial table-data copy.
```

For production-style logical replication setup, the initial data synchronization strategy must be planned carefully.

---

# 41. Test Write on Node A

Node A:

```sql
INSERT INTO orders (
    id,
    customer_id,
    order_status,
    total_amount
)
VALUES (
    1001,
    5001,
    'completed',
    750.00
);
```

Check Node B:

```sql
SELECT * FROM orders;
```

The row should appear.

# 42. Test Write on Node B

Node B:

```sql
INSERT INTO orders (
    id,
    customer_id,
    order_status,
    total_amount
)
VALUES (
    2001,
    7001,
    'pending',
    900.00
);
```

Then check Node A:

```sql
SELECT *
FROM orders
ORDER BY id;
```

The row should appear.

Now both directions work:

Both nodes are writable.

---

# 43. The Biggest Multi-Primary Problem: Conflicts

Consider the same row:

```text
order_id = 3000
```

Suppose Node A changes it:

```text
status = pending
```

while Node B independently changes it:

```text
status = completed
```

Now both nodes have independent changes.

When those changes are replicated, there is no universal rule that automatically determines the business-correct answer.

Possible problems include:

* Duplicate primary keys
* Conflicting updates
* Foreign key issues
* Different local state
* Replication worker failures
* Manual conflict resolution

A conflict can stop logical replication for the affected subscription and require investigation.

---

# 44. Global ID Generation

Multi-primary makes locally generated numeric IDs dangerous.

The two nodes can generate the same primary keys independently.

Logical replication can then encounter duplicate-key conflicts.

Safer approaches include:

### UUID

```sql
id UUID PRIMARY KEY
```

### Allocated ID ranges

For example:

```text
Node A → 1,000,000–1,999,999
Node B → 2,000,000–2,999,999
```

The exact production strategy depends on the application.

The important concept is:

> Independent writable nodes need a globally safe identifier strategy.

---

# 45. Schema Changes

Another important distinction:

Physical replication copies the database's storage-level state.

Logical replication is different.

Logical replication focuses on changes to replicated objects and does not automatically mean that arbitrary DDL changes on one node are applied to the other.

Therefore, schema migrations should be coordinated.

For example:

```text
Node A:
ALTER TABLE orders ADD COLUMN ...
```

does not mean that every subscriber magically receives the corresponding schema change.

A production deployment needs an explicit migration strategy.

---

# 46. Multi-Primary Use Cases

Multi-primary can be useful when multiple locations need to accept writes.

Potential reasons include:

* Regional write locality
* Local application availability
* Reducing write round-trip time between distant regions
* Operating multiple writable sites

However, this comes with significantly greater consistency complexity.

---

# 47. Primary/Replica vs Multi-Primary

| Feature                | Primary / Replica          | Multi-Primary    |
| ---------------------- | -------------------------- | ---------------- |
| Writable nodes         | One                        | Multiple         |
| Read replicas          | Yes                        | Possible         |
| Read scaling           | Yes                        | Yes              |
| Write scaling          | Mainly primary             | Multiple writers |
| Failover               | Possible                   | Different model  |
| Conflict management    | Relatively simple          | Major concern    |
| ID collisions          | Less problematic           | Important        |
| Schema management      | Relatively straightforward | More complex     |
| Consistency            | Easier                     | Harder           |
| Operational complexity | Lower                      | Higher           |

---


# 50. Important Production Considerations

Replication is not only about copying data.

A production replication design should consider:

## Replication lag

How far behind are replicas?

## Failover

How is a new primary selected?

## Fencing

How do we prevent the old primary from continuing to accept writes?

## Data loss

What is the acceptable RPO?

## Read consistency

Can the application tolerate stale reads?

## RTO

How quickly must the system recover?

## Monitoring

You should monitor:

* Replication state
* WAL position
* Replica lag
* Connection health
* Disk utilization
* Replication slots
* Failed replication workers

## Backups

Replication is not a replacement for backups.

If an application accidentally executes:

```sql
DELETE FROM orders;
```

the deletion can also replicate.

You still need independent backups and a recovery strategy.

---

# 51. Replication Is Not a Backup

This is extremely important.

Suppose:

```sql
DELETE FROM orders;
```

runs on the primary.

Replication faithfully copies that change

Now both databases have lost the data.

A production system needs both.

---

# 52. RTO and RPO

Two important disaster-recovery metrics are:

### RPO — Recovery Point Objective

How much data can be lost?

Can we lose 5 seconds of transactions?"
Can we lose 0 seconds?"


The key takeaway is:

> **Replication improves availability and allows read scaling, but it introduces consistency, lag, failover, and operational concerns. Multi-primary extends this by allowing multiple writers, but conflict management becomes a central design problem.**
