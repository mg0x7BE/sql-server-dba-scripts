/*
    Replication / Transactional replication
    Transactional replication latency and error troubleshooting.
*/

-- Replication system tables (MSrepl_*, MSdistribution_history, MStracer_*) live in
-- the distribution database. They are internal and undocumented; column shapes can
-- change between versions. Prefer the documented monitoring procs below where they
-- cover the need; treat the raw system-table queries as fragile and version-sensitive.

USE [distribution];
GO

-- List publications and their subscriptions. Start here to get the names/ids
-- you feed into the procs and queries that follow.
SELECT DISTINCT
       pb.publisher_db,
       da.subscriber_db,
       pb.publication,
       pd.id AS pub_db_id,
       da.id AS agent_id,
       CASE ps.status
            WHEN 0 THEN 'Inactive'
            WHEN 1 THEN 'Subscribed'
            WHEN 2 THEN 'Active'
       END   AS subs_status,
       pb.description
FROM dbo.MSpublications pb
     LEFT JOIN dbo.MSdistribution_agents da
            ON da.publication = pb.publication
           AND da.subscriber_db <> 'virtual'
     LEFT JOIN dbo.MSsubscriptions ps
            ON ps.publisher_db = pb.publisher_db
           AND ps.subscriber_db = da.subscriber_db
     JOIN dbo.MSpublisher_databases pd
            ON pb.publisher_db = pd.publisher_db;  -- in case there is no row in the agents table

-- Quick health/latency per subscription (documented Replication Monitor proc).
-- Run on the Distributor. First call lists subscriptions; pass the ids back in
-- to scope the result. Prefer this over the raw MStracer_* join below.
EXEC dbo.sp_replmonitorhelpsubscription
       @publisher = N'instance\name',
       @publication_type = 0;   -- 0 = transactional

-- Undistributed (pending) commands and estimated time to apply, per subscription.
-- The fastest answer to "how far behind is the subscriber and is it catching up".
EXEC dbo.sp_replmonitorsubscriptionpendingcmds
       @publisher = N'instance\name',
       @publisher_db = N'publisher_database',
       @publication = N'publication_name',
       @subscriber = N'instance\name',
       @subscriber_db = N'subscriber_database',
       @subscription_type = 0;  -- 0 = push

-- Logreader (publisher to distributor) and distribution (distributor to subscriber)
-- delivery latency, in seconds. Cheap counters, good for a dashboard / first glance.
SELECT instance_name,
       counter_name,
       cntr_value,
       ROUND(cntr_value / 1000.0, 0) AS latency_sec
FROM sys.dm_os_performance_counters
WHERE counter_name IN ('Logreader:Delivery Latency',
                       'Dist:Delivery Latency')
ORDER BY instance_name;

-- Post a tracer token to measure end-to-end latency on demand. Run against the
-- publication database on the Publisher. Note the returned tracer id.
EXEC sys.sp_posttracertoken @publication = N'publication_name';

-- List tracer tokens for a publication (documented). Use the publisher_commit
-- time to identify a specific token.
EXEC dbo.sp_helptracertokens
       @publisher = N'instance\name',
       @publication = N'publication_name',
       @publisher_db = N'publisher_database';

-- Per-token latency breakdown across publisher, distributor, and subscriber, documented.
-- NULL subscriber/overall latency means the token has not arrived yet, which also
-- makes Replication Monitor report a lag.
EXEC dbo.sp_helptracertokenhistory
       @publisher = N'instance\name',
       @publication = N'publication_name',
       @publisher_db = N'publisher_database',
       @tracer_id = 0;   -- from sp_helptracertokens

-- Latency from tracer tokens, all subscriptions, newest first. Raw-table version
-- of the proc above; keep for ad hoc filtering. Fragile: depends on MStracer_*
-- internals. Uncomment the WHERE block to filter.
SELECT ps.name                                                  AS publisher,
       p.publisher_db,
       p.publication,
       ss.name                                                  AS subscriber,
       da.subscriber_db,
       t.publisher_commit,
       t.distributor_commit,
       h.subscriber_commit,
       DATEDIFF(SECOND, t.publisher_commit, t.distributor_commit) AS [pub_to_dist_s],
       DATEDIFF(SECOND, t.distributor_commit, h.subscriber_commit) AS [dist_to_sub_s],
       DATEDIFF(SECOND, t.publisher_commit, h.subscriber_commit)   AS [total_latency_s]
FROM dbo.MStracer_tokens t
     INNER JOIN dbo.MStracer_history h ON h.parent_tracer_id = t.tracer_id
     INNER JOIN dbo.MSpublications p   ON p.publication_id = t.publication_id
     INNER JOIN dbo.MSdistribution_agents da ON da.id = h.agent_id
     INNER JOIN sys.servers ps ON ps.server_id = p.publisher_id
     INNER JOIN sys.servers ss ON ss.server_id = da.subscriber_id
/*
WHERE p.publisher_db = N'publisher_database'
  AND DATEDIFF(SECOND, t.publisher_commit, h.subscriber_commit) > 60   -- lag threshold
  AND ss.name = N'instance\name'                                       -- by subscriber
  AND p.publication = N'publication_name'                              -- by publication
  AND h.subscriber_commit IS NOT NULL                                  -- only completed tokens
*/
ORDER BY ps.name, p.publisher_db, p.publication, ss.name, da.subscriber_db,
         t.publisher_commit DESC;

-- Current lag per subscription, treating in-flight tracer tokens (NULL subscriber
-- commit) as "lagging since publisher_commit until now". Useful when a token is
-- stuck and the plain latency query shows NULL. Fragile: relies on MStracer_*.
;WITH Replication_Tracers AS
(
    SELECT ps.name AS publisher,
           p.publisher_db,
           p.publication,
           ss.name AS subscriber,
           da.subscriber_db,
           t.publisher_commit,
           DATEDIFF(SECOND, t.publisher_commit, h.subscriber_commit) AS total_latency_s
    FROM dbo.MStracer_tokens t
         INNER JOIN dbo.MStracer_history h ON h.parent_tracer_id = t.tracer_id
         INNER JOIN dbo.MSpublications p   ON p.publication_id = t.publication_id
         INNER JOIN dbo.MSdistribution_agents da ON da.id = h.agent_id
         INNER JOIN sys.servers ps ON ps.server_id = p.publisher_id
         INNER JOIN sys.servers ss ON ss.server_id = da.subscriber_id
),
Replication_Latency AS
(
    SELECT publisher, publisher_db, publication, subscriber, subscriber_db,
           publisher_commit, total_latency_s
    FROM Replication_Tracers
    WHERE publisher_commit > DATEADD(HOUR, -1, GETDATE())
      AND total_latency_s IS NOT NULL
    UNION
    SELECT publisher, publisher_db, publication, subscriber, subscriber_db,
           publisher_commit, total_latency_s
    FROM (
        SELECT publisher, publisher_db, publication, subscriber, subscriber_db,
               publisher_commit, total_latency_s,
               RANK() OVER (PARTITION BY publisher, publisher_db, publication, subscriber, subscriber_db
                            ORDER BY publisher_commit ASC) AS rn
        FROM Replication_Tracers
        WHERE total_latency_s IS NULL
    ) tmp
    WHERE tmp.rn = 1
)
SELECT publisher, publisher_db, publication, subscriber, subscriber_db,
       publisher_commit,
       ISNULL(total_latency_s, DATEDIFF(SECOND, publisher_commit, GETDATE())) AS lag_s,
       RANK() OVER (PARTITION BY publisher, publisher_db, publication, subscriber, subscriber_db
                    ORDER BY publisher_commit DESC) AS rn
FROM Replication_Latency;

-- Large transactions queued in the distribution database. Normal OLTP is a handful
-- of commands per transaction; batches 400-500. Transactions with thousands of
-- commands serialize the Distribution Agent and are a common lag cause.
-- Fragile: reads MSrepl_commands / MSrepl_transactions directly.
DECLARE @PublisherDb  sysname = N'publisher_database';
DECLARE @Since        datetime = CAST(CAST(GETDATE() AS date) AS datetime);  -- default: today

SELECT rt.entry_time, rt.xact_seqno, COUNT(*) AS command_count
FROM dbo.MSrepl_commands rc
     JOIN dbo.MSrepl_transactions rt    ON rc.xact_seqno = rt.xact_seqno
     JOIN dbo.MSpublisher_databases pd  ON pd.id = rc.publisher_database_id
WHERE rt.entry_time >= @Since
  AND pd.publisher_db = @PublisherDb
GROUP BY rt.entry_time, rt.xact_seqno
HAVING COUNT(*) > 1000
ORDER BY command_count DESC;

-- Watch a slow agent move: compare cmds applied between recent history rows to see
-- if it is progressing and how fast. Get the agent id from the first publication
-- query (MSdistribution_agents.id). Fragile: parses the MSdistribution_history XML.
DECLARE @AgentId int = 0;   -- distribution agent id

;WITH CTE1 AS (
    SELECT TOP (10)
           ROW_NUMBER() OVER (ORDER BY dh.xact_seqno DESC, dh.time DESC) AS rownum,
           CONVERT(xml, dh.comments).value('(/stats/@cmds)[1]', 'int')  AS stats_cmds,
           CONVERT(xml, dh.comments).value('(/stats/@state)[1]', 'int') AS stats_state,
           CONVERT(xml, dh.comments).value('(/stats/@work)[1]', 'int')  AS stats_work,
           CONVERT(xml, dh.comments).value('(/stats/@idle)[1]', 'int')  AS stats_idle,
           dh.time,
           dh.xact_seqno
    FROM dbo.MSdistribution_history dh WITH (NOLOCK)
    WHERE dh.agent_id = @AgentId
    ORDER BY dh.xact_seqno DESC, dh.time DESC
)
SELECT c1.stats_cmds - c2.stats_cmds AS cmd_diff,
       DATEDIFF(MINUTE, c2.time, c1.time) AS mins,
       c1.*
FROM CTE1 c1
     LEFT JOIN CTE1 c2 ON c1.rownum = c2.rownum - 1;

-- Last replicated xact_seqno for a named subscriber, the seed the undistributed
-- (pending) queries below need. Highest seqno delivered to that subscriber_db.
-- Fragile: reads MSsubscriptions / MSpublications / MSdistribution_history directly.
DECLARE @SubscriberDb sysname = N'subscriber_database';

SELECT MAX(dh.xact_seqno) AS last_xact_seqno
FROM dbo.MSsubscriptions s
     JOIN dbo.MSpublications p          ON p.publication_id = s.publication_id
     JOIN dbo.MSdistribution_history dh ON dh.agent_id = s.distribution_agent
WHERE s.subscriber_db = @SubscriberDb;

-- Given the last replicated xact_seqno, find the next transaction being applied
-- and how many commands it carries. Use to size the transaction currently blocking
-- the agent. Fragile: reads MSrepl_transactions / MSrepl_commands directly.
DECLARE @PublisherDatabaseId int = 0;                                   -- MSpublisher_databases.id
DECLARE @LastXactSeqno       varbinary(16) = 0x00000000000000000000000000000000;  -- from the query above

SELECT TOP (1) *
FROM dbo.MSrepl_transactions WITH (NOLOCK)
WHERE publisher_database_id = @PublisherDatabaseId
  AND xact_seqno > @LastXactSeqno
ORDER BY xact_seqno ASC;

-- Command count for a given transaction (plug in the xact_seqno from above).
SELECT COUNT(*) AS command_count
FROM dbo.MSrepl_commands
WHERE xact_seqno = @LastXactSeqno
  AND publisher_database_id = @PublisherDatabaseId;

-- A failed command reports a "Transaction sequence number" and "Command ID" in the
-- Distribution Agent error. Use them to find the offending transaction, the article
-- (table) it targets, and the actual command text.
DECLARE @XactSeqno varbinary(16) = 0x00000000000000000000000000000000;   -- from the agent error
DECLARE @CommandId int = 0;                                              -- from the agent error
DECLARE @PubDbId   int = 0;                                              -- MSpublisher_databases.id

SELECT * FROM dbo.MSrepl_transactions WHERE xact_seqno = @XactSeqno;

SELECT * FROM dbo.MSrepl_commands     WHERE xact_seqno = @XactSeqno;

-- Article (table) the failing command runs against.
SELECT *
FROM dbo.MSarticles
WHERE article_id IN (SELECT article_id FROM dbo.MSrepl_commands WHERE xact_seqno = @XactSeqno);

-- Reconstruct the actual command and the row (primary key) it targeted.
-- sp_browsereplcmds is undocumented and may change between versions; read-only.
EXEC sys.sp_browsereplcmds
       @xact_seqno_start = @XactSeqno,
       @xact_seqno_end   = @XactSeqno,
       @command_id       = @CommandId,
       @publisher_database_id = @PubDbId;

-- Fix for "Cannot insert explicit value for identity column ... IDENTITY_INSERT is
-- set to OFF" (error 544). Happens when a subscriber/publisher copy was taken before
-- the publication existed, so identity columns are not flagged "for replication".
-- Flags every identity column in the current database via an explicit cursor over
-- sys.identity_columns. Run in the affected database, not in distribution.
-- Changes metadata on every identity column - review the target database first.
/*
USE [target_database];
GO
DECLARE @ObjectId int;
DECLARE id_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT object_id
    FROM sys.identity_columns
    WHERE OBJECTPROPERTY(object_id, 'IsUserTable') = 1;
OPEN id_cur;
FETCH NEXT FROM id_cur INTO @ObjectId;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sys.sp_identitycolumnforreplication @ObjectId, 1;
    FETCH NEXT FROM id_cur INTO @ObjectId;
END
CLOSE id_cur;
DEALLOCATE id_cur;
GO
*/

-- Remove a faulty (stuck, never-completing) tracer token so it stops being reported
-- as lag by the monitors. Destructive: deletes tracer history. Confirm the tracer id
-- with sp_helptracertokens / sp_helptracertokenhistory first, then uncomment.
/*
EXEC dbo.sp_deletetracertokenhistory
       @publisher = N'instance\name',
       @publication = N'publication_name',
       @publisher_db = N'publisher_database',
       @tracer_id = 0;
*/

-- Trim distribution history retention. Destructive cleanup: removes monitoring
-- history older than the retention window (hours). Uncomment to run.
/*
EXEC dbo.sp_MShistory_cleanup @history_retention = 72;   -- hours
*/
