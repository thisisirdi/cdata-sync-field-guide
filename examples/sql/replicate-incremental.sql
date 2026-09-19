-- Incremental replication filter patterns.
-- See docs/07-incremental-replication.md


------------------------------------------------------------------
-- A. Open-ended: everything since the last successful run
------------------------------------------------------------------
-- The common case. Start here.
--
-- Note >= rather than >. Using > risks missing rows that share the
-- boundary timestamp; >= risks re-reading a few, which is harmless
-- when the primary key is correct because the upsert is idempotent.
-- Prefer the harmless failure.
WHERE LastUpdated >= REPLICATE_LASTMODTIME()


------------------------------------------------------------------
-- B. Bounded window, for APIs that require from/to parameters
------------------------------------------------------------------
-- Some reporting APIs will not accept an open-ended filter.
-- Requires ReplicateInterval and ReplicateIntervalUnit to be set,
-- since those define the window.
WHERE from_date_prompt = REPLICATE_LASTMODTIME()
  AND to_date_prompt   = REPLICATE_NEXTINTERVAL()


------------------------------------------------------------------
-- C. Closed window on a single column
------------------------------------------------------------------
-- Bounds the size of any single run, which matters when the source
-- is slow or fragile.
WHERE ModifiedAt >= REPLICATE_LASTMODTIME()
  AND ModifiedAt <  REPLICATE_NEXTINTERVAL()


------------------------------------------------------------------
-- Full example
------------------------------------------------------------------
REPLICATE [Orders]
(
    OrderId    INT,
    CustomerId INT,
    OrderTotal DECIMAL(18,2),
    ModifiedAt DATETIME,
    PRIMARY KEY (OrderId)
)
WITH BatchSize='5000'
SELECT OrderId, CustomerId, OrderTotal, ModifiedAt
FROM Orders
WHERE ModifiedAt >= REPLICATE_LASTMODTIME();


------------------------------------------------------------------
-- Commissioning checks — run these against the SOURCE
------------------------------------------------------------------

-- 1. Future-dated rows will poison the high-water mark and stop
--    replication silently. Compare this to the current time in the
--    SOURCE's timezone.
SELECT MAX(ModifiedAt) AS max_modified FROM Orders;

-- 2. Nulls in the check column never replicate.
SELECT COUNT(*) AS null_check_column
FROM Orders
WHERE ModifiedAt IS NULL;

-- 3. Does the column actually move when a row changes? Update one
--    row through the application, not directly in SQL, and confirm
--    the timestamp advanced. An application-set UpdatedAt that some
--    code paths forget is a silent data loss bug.


------------------------------------------------------------------
-- The thirty-second test that catches everything
------------------------------------------------------------------
-- Run the job twice with no source changes in between.
-- Second run should move ZERO rows.
-- If it moves everything, the incremental filter is not applied.
