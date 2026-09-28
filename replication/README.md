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
* Replication slots
* Split-brain
* Logical replication
* Multi-primary / bidirectional replication
* Conflict handling


---

# 1. What Is Database Replication?

Database replication means maintaining a copy of database data on another database server.

With a primary/replica architecture:

```text
                ┌──────────────┐
                │   PRIMARY    │
                │ PostgreSQL   │
                └──────┬───────┘
                       │
                       │ WAL
                       ▼
                ┌──────────────┐
                │   REPLICA    │
                │ PostgreSQL   │
                └──────────────┘
```

The primary accepts writes.

The replica receives changes from the primary and replays them.

A typical application architecture is:

```text
                Application
                 /       \
                /         \
             WRITE        READ
               |            |
               ▼            ▼
          ┌─────────┐  ┌─────────┐
          │ Primary │  │ Replica │
          └────┬────┘  └─────────┘
               │
               │ WAL
               └──────────────►
```

Replication is different from sharding.

### Replication

Every database contains the same dataset:

```text
Primary  →  full dataset
Replica  →  full dataset
```

### Sharding

Each database contains part of the dataset:

```text
Shard 1 → customers 1–50,000
Shard 2 → customers 50,001–100,000
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

# 2. Project Structure

Replication is implemented at the root of the repository.

```text
database-design-and-scaling-guide/
│
├── docker-compose.yml
│
├── primary/
│   ├── init.sql
│   └── pg_hba.conf
│
└── multi-primary/
    ├── node-a/
    │   ├── init.sql
    │   └── pg_hba.conf
    │
    └── node-b/
        ├── init.sql
        └── pg_hba.conf
```

We intentionally use the standard PostgreSQL Docker image.

There is no custom Dockerfile.

---

# 3. Primary / Replica Lab

The first replication model is:

```text
Primary → Replica
```

The primary is writable.

The replica is read-only while it is acting as a standby.

---

# 4. Docker Configuration

The primary uses PostgreSQL 17:

```yaml
postgres-primary:
  image: postgres:17
  container_name: scaling-primary
  environment:
    POSTGRES_USER: repluser
    POSTGRES_PASSWORD: replpassword
    POSTGRES_DB: replication_primary
  ports:
    - "5435:5432"
  volumes:
    - primary_data:/var/lib/postgresql/data
    - ./primary/init.sql:/docker-entrypoint-initdb.d/init.sql
    - ./primary/pg_hba.conf:/etc/postgresql/pg_hba.conf
  command:
    - postgres
    - -c
    - wal_level=replica
    - -c
    - max_wal_senders=10
    - -c
    - hba_file=/etc/postgresql/pg_hba.conf
```

The replica uses another PostgreSQL 17 container:

```yaml
postgres-replica:
  image: postgres:17
  container_name: scaling-replica
  environment:
    PGPASSWORD: replpassword
  ports:
    - "5436:5432"
  depends_on:
    - postgres-primary
  volumes:
    - replica_data:/var/lib/postgresql/data
  command:
    - bash
    - -c
    - |
      until pg_isready -h scaling-primary -p 5432 -U repluser; do
        sleep 1
      done

      if [ ! -s "$$PGDATA/PG_VERSION" ]; then
        rm -rf "$$PGDATA"/*
        pg_basebackup \
          -h scaling-primary \
          -p 5432 \
          -U repluser \
          -D "$$PGDATA" \
          -Fp \
          -Xs \
          -P \
          -R
      fi

      exec postgres
```

Volumes:

```yaml
volumes:
  primary_data:
  replica_data:
```

---

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

# 9. Start the Replication Lab

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

Expected:

```text
1001 | 1001 | completed | 500.00
1002 | 1002 | pending   | 750.00
1003 | 1003 | completed | 1200.00
```

The exact formatting depends on `psql`.

---

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

The same rows should be present.

The flow is:

```text
Primary
   │
   │ pg_basebackup
   ▼
Replica
```

This gives the replica an initial copy of the primary data.

---

# 12. Why `pg_basebackup` Is Required

A new replica cannot simply start with an empty PostgreSQL database and begin replaying changes.

The replica needs an initial copy.

The process is:

```text
Primary database
       │
       ▼
pg_basebackup
       │
       ▼
Replica receives initial database copy
       │
       ▼
Replica starts consuming WAL
```

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

Expected:

```text
 t
```

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

```text
state       = streaming
sync_state  = async
```

This verifies that the replica has established a streaming replication connection.

---

# 15. How Streaming Replication Works

PostgreSQL uses the Write-Ahead Log (WAL).

Instead of repeatedly copying the whole database, PostgreSQL records database changes in WAL.

Conceptually:

```text
INSERT
  │
  ▼
WAL record
  │
  ▼
Primary WAL
  │
  ▼
WAL sender
  │
  ▼
Network
  │
  ▼
WAL receiver
  │
  ▼
Replica replays WAL
```

A simplified example:

```text
INSERT order 1004
       │
       ▼
Primary generates WAL
       │
       ▼
Replica receives WAL
       │
       ▼
Replica replays WAL
       │
       ▼
Order 1004 appears on replica
```

---

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

Then check the replica:

```sql
SELECT * FROM orders
ORDER BY id;
```

The new order should eventually appear on the replica.

The important point is:

```text
Application
     │
     │ INSERT
     ▼
Primary
     │
     │ WAL
     ▼
Replica
```

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

The normal architecture is:

```text
WRITE
  │
  ▼
PRIMARY

READ
  │
  ▼
REPLICA
```

This allows read traffic to be distributed across replicas.

---

# 18. Read Scaling

Without replicas:

```text
                Application
                    │
                    ▼
                 Primary
              /    |    \
           READ  READ   READ
```

With replicas:

```text
                Application
                 /       \
              WRITE      READ
                │          │
                ▼          ▼
             Primary    Replica
```

With multiple replicas:

```text
                    Primary
                   /   |   \
                  /    |    \
                 ▼     ▼     ▼
            Replica1 Replica2 Replica3
```

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

Conceptually:

```text
Primary WAL position
        │
        │ difference
        ▼
Replica replay position
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

Example:

```text
POST /orders
     │
     ▼
Primary
     │
     ├── commit
     │
     └── WAL ─────► Replica
                       │
                    not replayed yet

GET /orders
     │
     ▼
Replica
     │
     └── old state
```

This creates a read-after-write consistency issue.

A common application strategy is:

```text
Normal reads
    ↓
Replica

Immediate read after a write
    ↓
Primary
```

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

```text
Primary
   X
   │
Replica
   │
   └── still read-only
```

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
FROM orders
WHERE customer_id = 2000;
```

The old replica has now become the new primary.

Architecture:

```text
BEFORE

Primary ───────► Replica
  RW                RO


AFTER PROMOTION

Old Primary
     X

New Primary
     │
     └── RW
```

---

# 26. Promotion Is Not the Same as Automatic Failover

The promotion command was manual:

```bash
pg_ctl promote
```

PostgreSQL replication itself did not:

```text
detect failure
+
elect a new primary
+
change the application endpoint
+
reconfigure other replicas
```

A production HA system typically adds an orchestration/failover layer or uses a managed PostgreSQL service.

The important distinction is:

```text
Replication
    =
maintain another copy

Failover
    =
change database roles after failure
```

---

# 27. What Happens When the Old Primary Comes Back?

This is critical.

Suppose:

```text
Old Primary
     X

New Primary
     │
     └── accepts new writes
```

The old primary is now potentially out of date.

It should not simply be considered a healthy replica and immediately put back into service.

The old primary may contain a different transaction history.

Conceptually:

```text
Old Primary
    history A

New Primary
    history A + new writes
```

The old primary needs to be rebuilt/rejoined as a standby of the new primary.

Typical process:

```text
Old Primary
    │
    ▼
Discard/rebuild old state
    │
    ▼
pg_basebackup from new primary
    │
    ▼
Start as standby
    │
    ▼
Stream WAL
```

This is known as re-provisioning or rejoining the old primary.

---

# 28. Asynchronous Replication and Possible Data Loss

Our primary/replica lab uses:

```text
sync_state = async
```

The primary doesn't wait for the replica to replay every change before acknowledging the transaction.

Potential scenario:

```text
T1
Write order A

Primary commits
    │
    ├── application receives success
    │
    ▼
WAL still hasn't reached/replayed on replica

T2
Primary crashes
```

After promotion:

```text
Replica
   │
   └── order A may not exist
```

Therefore asynchronous replication can potentially lose the most recent transactions that had not reached the replica.

This is the main durability tradeoff of asynchronous replication.

---

# 29. RPO

RPO means:

# Recovery Point Objective

It answers:

> How much recently committed data could potentially be lost after a failure?

With asynchronous replication:

```text
Potentially some recent transactions
```

With properly configured synchronous replication:

```text
Much stronger protection against losing acknowledged transactions
```

There are still important operational nuances, but the tradeoff is the key concept.

---

# 30. Synchronous Replication

PostgreSQL also supports synchronous replication.

Conceptually:

```text
Application
     │
     ▼
Primary
     │
     │ WAL
     ▼
Replica
     │
     │ acknowledgement
     ▼
Primary
     │
     ▼
Commit acknowledged
     │
     ▼
Application
```

In asynchronous replication:

```text
Application
     │
     ▼
Primary
     │
     ├── commit
     │
     └── WAL → Replica
```

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

# 31. Replication Slots

PostgreSQL replication slots help ensure that required WAL is retained for a replica.

Conceptually:

```text
Primary
  │
  ├── WAL 101
  ├── WAL 102
  ├── WAL 103
  ├── WAL 104
  │
  └── Replica is currently at WAL 102
```

The primary must retain WAL needed by the replica.

A replication slot can track the replica's required WAL position.

However, replication slots create another operational risk.

If a replica disappears permanently:

```text
Replica fails
      │
      ▼
Replication slot remains
      │
      ▼
Primary keeps retaining WAL
      │
      ▼
WAL directory grows
      │
      ▼
Disk usage increases
```

A poorly managed replication slot can eventually contribute to disk exhaustion.

Therefore:

```text
Replication slots
+
Monitoring
```

must go together.

We intentionally did not add a replication slot to the first simple Docker lab because the goal was to demonstrate the core mechanism without introducing unnecessary operational complexity.

---

# 32. Split-Brain

One of the most dangerous distributed database problems is split-brain.

Imagine the primary becomes unreachable from the application or monitoring system, but is still running.

Another server gets promoted:

```text
               Network partition

        ┌─────────────┐
        │ Old Primary │
        │     RW      │
        └─────────────┘

               X X X

        ┌─────────────┐
        │ New Primary │
        │     RW      │
        └─────────────┘
```

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
Primary → Replica
```

we configure:

```text
Node A ◄────────► Node B
```

Both nodes are writable.

```text
Node A
  RW
  ▲
  │
  │ logical replication
  │
  ▼
Node B
  RW
```

This is commonly described as:

* Multi-primary
* Multi-master
* Bidirectional replication

In this lab, PostgreSQL logical replication is used to demonstrate the mechanics.

---

# 34. Why Logical Replication?

Physical replication is used for the primary/standby model.

Logical replication works at the logical change level.

It allows us to define:

```text
Publication
     │
     ▼
Tables whose changes are published
     │
     ▼
Subscription
     │
     ▼
Target database
```

This gives us the ability to build:

```text
A publishes → B subscribes
B publishes → A subscribes
```

---

# 35. Multi-Primary Docker Services

We use two PostgreSQL 17 containers.

Node A:

```yaml
postgres-multi-a:
  image: postgres:17
  container_name: scaling-multi-a
  environment:
    POSTGRES_USER: repluser
    POSTGRES_PASSWORD: replpassword
    POSTGRES_DB: multi_primary
  ports:
    - "5437:5432"
  volumes:
    - multi_a_data:/var/lib/postgresql/data
    - ./multi-primary/node-a/init.sql:/docker-entrypoint-initdb.d/init.sql
    - ./multi-primary/node-a/pg_hba.conf:/etc/postgresql/pg_hba.conf
  command:
    - postgres
    - -c
    - wal_level=logical
    - -c
    - max_wal_senders=10
    - -c
    - max_replication_slots=10
    - -c
    - hba_file=/etc/postgresql/pg_hba.conf
```

Node B:

```yaml
postgres-multi-b:
  image: postgres:17
  container_name: scaling-multi-b
  environment:
    POSTGRES_USER: repluser
    POSTGRES_PASSWORD: replpassword
    POSTGRES_DB: multi_primary
  ports:
    - "5438:5432"
  volumes:
    - multi_b_data:/var/lib/postgresql/data
    - ./multi-primary/node-b/init.sql:/docker-entrypoint-initdb.d/init.sql
    - ./multi-primary/node-b/pg_hba.conf:/etc/postgresql/pg_hba.conf
  command:
    - postgres
    - -c
    - wal_level=logical
    - -c
    - max_wal_senders=10
    - -c
    - max_replication_slots=10
    - -c
    - hba_file=/etc/postgresql/pg_hba.conf
```

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

Conceptually:

```text
Node A
   │
   └── publishes changes to orders
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

This means:

```text
Node B
   │
   └── subscribes to Node A
```

Then on Node A:

```sql
CREATE SUBSCRIPTION node_a_subscribes_to_b
CONNECTION 'host=postgres-multi-b port=5432 user=repluser password=replpassword dbname=multi_primary'
PUBLICATION node_b_publication
WITH (copy_data = false);
```

Now:

```text
Node A ◄──────────────► Node B
  RW                      RW
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

Flow:

```text
Node A
  │
  │ INSERT
  ▼
Publication
  │
  ▼
Subscription
  │
  ▼
Node B
```

---

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

```text
             INSERT
Node A ─────────────────► Node B
  ▲                           │
  │                           │
  └───────────────────────────┘
             INSERT
```

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

Therefore:

```text
Multi-primary
=
multiple writable nodes
+
conflict management
```

---

# 44. Global ID Generation

Multi-primary makes locally generated numeric IDs dangerous.

For example:

```text
Node A:
1
2
3
4

Node B:
1
2
3
4
```

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

Example:

```text
             Global Application

            /                 \
           ▼                   ▼
       Node A                Node B
      Europe                Asia
         RW                    RW
           \                   /
            └──── replicate ──┘
```

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

# 48. Replication vs Sharding

This distinction is fundamental.

## Replication

Copies data:

```text
Primary
   │
   ▼
Replica
```

Both contain the same dataset.

Purpose:

```text
Availability
Read scaling
Durability
```

## Sharding

Splits data:

```text
Shard 1
   +
Shard 2
```

Each contains part of the dataset.

Purpose:

```text
Data scaling
Write scaling
Storage scaling
```

You can combine them.

---

# 49. Sharding + Replication

A large production architecture could look like:

```text
                    Application
                         │
                    Shard Router
                    /          \
                   /            \
                  ▼              ▼

             Shard 1          Shard 2
               │                │
          ┌────┴────┐      ┌────┴────┐
          │         │      │         │
       Primary   Replica Primary   Replica
          │         │      │         │
          └───rep───┘      └───rep───┘
```

Now we solve multiple problems:

### Sharding

Allows data to be distributed across multiple database servers.

### Replication

Provides additional copies for availability and read scaling.

This is much closer to the architecture used by large distributed systems.

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

Replication faithfully copies that change:

```text
DELETE
  │
  ▼
Primary
  │
  ▼
Replica
```

Now both databases have lost the data.

Therefore:

```text
Replication
!=
Backup
```

A production system needs both.

---

# 52. RTO and RPO

Two important disaster-recovery metrics are:

### RPO — Recovery Point Objective

How much data can be lost?

```text
"Can we lose 5 seconds of transactions?"
"Can we lose 0 seconds?"
```

### RTO — Recovery Time Objective

How long can recovery take?

```text
"Must recover within 30 seconds?"
"Within 10 minutes?"
```

Replication configuration should be designed around these requirements.

---

# 53. Common Failure Scenarios

## Scenario 1 — Replica fails

```text
Primary ───X─── Replica
```

Primary can continue serving writes.

Restore the replica and let it catch up.

---

## Scenario 2 — Primary fails

```text
Primary
   X

Replica
```

Promotion may be required:

```text
Replica
   │
   ▼
New Primary
```

---

## Scenario 3 — Replica is far behind

```text
Primary
   │
   │ lots of WAL
   ▼
Replica
   │
   └── replaying slowly
```

Monitor lag.

Determine whether the replica can catch up or needs to be rebuilt.

---

## Scenario 4 — Network partition

```text
Primary  X  Replica
```

Do not blindly promote both sides.

Otherwise split-brain can occur.

---

## Scenario 5 — Accidental DELETE

```text
Primary
   │
   ▼
Replica
```

Both receive the delete.

Restore from backup rather than relying on replication.

---

# 54. Useful PostgreSQL Commands

### Check whether the server is a standby

```sql
SELECT pg_is_in_recovery();
```

### View connected replicas on a primary

```sql
SELECT
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;
```

### Estimate WAL replay lag

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

### Check logical subscriptions

```sql
SELECT
    subname,
    subenabled
FROM pg_subscription;
```

---

# 55. Useful Docker Commands

Start:

```bash
docker compose up -d
```

Stop containers:

```bash
docker compose down
```

Stop and remove database volumes:

```bash
docker compose down -v
```

See containers:

```bash
docker ps
```

Stop primary:

```bash
docker kill scaling-primary
```

Stop replica:

```bash
docker stop scaling-replica
```

Start replica:

```bash
docker start scaling-replica
```

Promote replica:

```bash
docker exec scaling-replica \
pg_ctl promote -D /var/lib/postgresql/data
```

Connect to primary:

```bash
docker exec -it scaling-primary \
psql -U repluser -d replication_primary
```

Connect to replica:

```bash
docker exec -it scaling-replica \
psql -U repluser -d replication_primary
```

---

# 56. Troubleshooting

## Replica does not start

Check logs:

```bash
docker logs scaling-replica
```

Check whether the primary is reachable:

```bash
docker exec scaling-replica \
pg_isready -h scaling-primary -p 5432 -U repluser
```

---

## Replica cannot connect to primary

Check:

```text
pg_hba.conf
```

and make sure the replication connection is allowed.

Also verify that:

```text
wal_level=replica
```

is configured on the primary.

---

## Replica does not contain newly inserted rows

Check the primary:

```sql
SELECT * FROM pg_stat_replication;
```

Then check:

```text
state
sync_state
replay_lsn
```

Also check:

```bash
docker logs scaling-replica
```

---

## Changes do not replicate in the multi-primary lab

Check subscriptions:

```sql
SELECT
    subname,
    subenabled
FROM pg_subscription;
```

Check the PostgreSQL logs for the subscription worker.

Also verify:

```text
wal_level=logical
```

on both nodes.

---

# 57. Key Lessons

The most important mental model from this section is:

```text
Replication
    ↓
Another copy of the database
```

Then build on top of it:

```text
Replication
    ↓
WAL
    ↓
Primary / Replica
    ↓
Replication Lag
    ↓
Read Scaling
    ↓
Failure Detection
    ↓
Failover
    ↓
Promotion
    ↓
Rejoining
```

For multi-primary:

```text
Logical Replication
    ↓
Publication
    ↓
Subscription
    ↓
Bidirectional Replication
    ↓
Multiple Writers
    ↓
Conflict Management
    ↓
Global ID Strategy
```

---

# 58. Final Mental Model

Remember these four concepts:

```text
PARTITIONING
-----------------------------
Split data inside one database


SHARDING
-----------------------------
Split data across databases


REPLICATION
-----------------------------
Copy data across databases


MULTI-PRIMARY
-----------------------------
Multiple databases accept writes
and replicate changes between them
```

Or even simpler:

```text
Partitioning
     ↓
"Split the table"

Sharding
     ↓
"Split the data"

Replication
     ↓
"Copy the data"

Multi-primary
     ↓
"Multiple copies can accept writes"
```

---

# 59. What This Lab Demonstrated

This repository now demonstrates:

```text
PostgreSQL 17
     │
     ├── Primary / Replica
     │      │
     │      ├── WAL
     │      ├── Streaming replication
     │      ├── Read scaling
     │      ├── Replica lag
     │      ├── Read-after-write
     │      ├── Primary failure
     │      ├── Promotion
     │      └── Failover concepts
     │
     └── Multi-Primary
            │
            ├── Logical replication
            ├── Publications
            ├── Subscriptions
            ├── Bidirectional writes
            ├── Conflict risks
            └── Global ID considerations
```

The key takeaway is:

> **Replication improves availability and allows read scaling, but it introduces consistency, lag, failover, and operational concerns. Multi-primary extends this by allowing multiple writers, but conflict management becomes a central design problem.**

## Next Topic

The replication section can now be considered complete. The remaining major database-scaling topic in this project is to combine what we learned into **real-world architecture patterns**, such as:

```text
Caching
   +
Indexes
   +
Partitioning
   +
Sharding
   +
Replication
```

and understand **when to use which technique, what bottleneck each one solves, and how they work together in a production system**.
