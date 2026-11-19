## PostgreSQL Internals

The goal of this study is to make sure that I understand the internals of postgres and the mechanic trade-offs behind Postgres design: why updates generate disk bloat, how crash recovery guarantee durability without sacrificing write throughput and how consensus layers prevent split-brain failures.

### Physical Storage Architecture

The data stored in postgres is stored as raw binary files organized inside a directory known as `PGDATA`. In this directory every database has a subdirectory called `base/` and every table or index is stored as one or more binary files.
In Postgres, a table's main data file is called a heap because rows are stored in no particular order—wherever Postgres finds free space, it drops the row in. (Unlike indexes, which keep data strictly sorted.)

### Indexes & Access Methods

Without an index, filtering a table requires a Sequential Scan -> read every page  of the heap from start to finish. An index is a separate binary relationship between the column keys paired with physical CTID pointer back to the heap.
You can have different index types and each one of those B-tree, GIN, GiST, BRIN -> each one of those has its on advantages for specific use cases.
When you create a table with a primary key or a unique constrain -> postgres create indexes for the table out of the box. But if nothing is specified on the creation, it is forced to do a sequential scan in the case of a SELECT.
The B-tree works by saving a column key sorted + a pointer to the page number and item id in the heap.


**Interesting fact about indexes and how table operation works**

We now know that an index is used to make the select clause faster, because we have less hops to find a certain record based on a key. The problem is that, the index keep the position of records on the heap and in the case of an UPDATE of a row, the row in the heap is flagged as dead and a new row on a new page is created. What happened to the index so? The index remains with the old position of the record for that given row, not the new position of the updated row.
So, when the new row is in a select clause, it gets until the index and see two records for that given key and two positions -> in that read Postgres will identify which is the new record an then erase the old dead record from the index.
What happens in the heap? Well, the old record remains in the heap, but it is "invisible" for the SELECT clause.
In a large scale our heap will start having more and more dead records and this occupy an unnecessary space -> this phenomenon is called BLOATING. Bloating is the fact that dead records are accumulated in the heap of our database and sooner or later they should be cleaned to free space in the database.

What is the problem with indexing???? Well, indexes makes reading operations faster, but the other write operations and delete remains kind of the same because for example, during a write operation we need to update all indexes on that table, because we need to match the new INSERT or UPDATE records in all indexes -> I/O disk operation increases, the contant needs to be lock during this operations and there is a big WAL generation.

### Write-Ahead Logging (WAL)

The WAL is a append-only stream of binary change records stored in the folder `pg_wal` - they have 1 per postgres instance. It enforces the postgres durability rule: **no modified
data page may be written to disk until the WAL records describing that change have
been flushed to durable storage.**.

The WAL makes postgres fast and safe. Before writing any changes to the disk, postgres changes pages in memory (shared buffers) and write a sequential log record to the WAL. On COMMIT -> Postgres flushes only the sequential WAL buffer to disk.
For example, when you run an INSERT, UPDATE, or DELETE and COMMIT:

```bash
1. Modify in RAM       [ Shared Buffers (8 KB Heap/Index Pages in Memory) ]
                                  │
                                  ▼  (Also generates a WAL record in WAL Buffers)
2. Flush Log on COMMIT [ $PGDATA/pg_wal/000000010000000000000001 ]  <-- Sequential write (Fast!)
                                  │
                                  ▼  (Much later, asynchronously in the background)
3. Flush Pages to Disk [ $PGDATA/base/<db_oid>/<relfilenode> ]    <-- Random I/O by Checkpointer / BgWriter

```

- Crash Recovery: If the server crashes before dirty pages in Shared Buffers are written to table
files, Postgres restarts, locates the last valid checkpoint, and replays the WAL forward to restore
all committed transactions
- Checkpoints: Periodically, a background checkpointer flushes all dirty pages from Shared
Buffers to the main heap and index files on disk, then writes a checkpoint record to the WAL.
Once a checkpoint completes, older WAL segments are no longer needed for crash recovery and
can be recycled or archived.
- Streaming Replication: Read replicas stay synchronized by opening a network connection to
the primary and continuously streaming and replaying WAL records in real time.


### Bloat, VACUUM & Transaction Wraparound
Left uncleaned, dead tuples accumulate inside heap and index pages—a condition called Bloat—causing sequential and index scans to read wasted space.

**How VACUUM reclaims space:** VACUUM is the postgres background garbage collector - it operates concurrently without blocking reads and writes. First it scans the heap and collect the CTID's of the dead duplicates. With those ids it goes to the indexes and removes all the entries to those dead duplicates which it collect the ids. In the end it deletes the dead tuples from the heap and update the FSM (Free Space Map) and mark clean pages in the visibility map (VM).

 - Important: when executing a normal VACUUM any read and write is blocked, but also any file on OS disk is shrinked. But in the case of a VACUUM FULL is blocks read and writes for a period so it can optimize also the OS disk files.
 - A good postgres extension to do that it is called pg_repack -> it optimize the os files in the disk with a minimum block by building shadow tables and swap.

### Backups & Point-In-Time Recovery (PITR)

Production backup architecture rely on two complementary methods:
**Logical Backups:** Tools as pg_dump and pgdumpall create queries that copies the schema DDL and row data as SQL scripts. This makes a backup portable between different postgres versions. They represent a single point in time snapshot of the database and are slow to restore very big databases because they need to recreate the whole database through the engine.
**Physical Backups & PITR:** Tool pg_basebackup copies the whole PGDATA directory to a cloud object storage without interrupting database traffic.

**Continuous Archiving with WAL-G:**
- backup-push -> periodically copy PGDATA to a storage.
- archive_command -> stores WAL in the storage.
- backup-fetch + wal-fetch from the storage so that the base is restored and the wal is replayed until the PIT for the backup.

### High Availability with Patroni
Postgres has a builtin streaming replication, but it doesnt have a distributed consensus for a leader selection. This can create the dangerous state of split-brain condition, where divergent writes happened in two different leaders and it would corrupt the cluster state.

**Patroni Architecture & Consensus**
Patroni is a cluster orchestrator that runs with postgres in every node -> it coordinates automatic failover though a DCS (distributed consensus store).
The leader is always communicating with the DCS, once it fails patroni starts the failover -> demotes actual leader and start the electio of new leader by comparing the WAL of the other replicas -> the one with the most up to date WAL becomes the new leader.
The leader is a read/write replica, but the other replicas are read only -> this avoid the split brain.
The trafic happenes through a HAproxy of a PGBOUNCER communicating with the replicas and checking via http in the port 8008 by two different endpoints: replica or primary -> one of those needs to return a 200 so the proxy knows to whom send the trafic for read or write.