-- CHECKCACHE reconciliation patterns.
--
-- CHECKCACHE only ever writes to the DESTINATION. The source is
-- read, never modified.
--
-- WITH REPAIR deletes rows. If the source query is wrong, or the
-- source is mid-outage and returning partial results, reconciliation
-- will faithfully delete everything the source did not return.
-- Confirm the source is healthy before enabling repair on production.
--
-- See docs/09-checkcache-reconciliation.md


------------------------------------------------------------------
-- 1. Full validation and repair
------------------------------------------------------------------
-- Inserts what is missing, updates what differs, deletes what is
-- gone. Correct and thorough. Reads the entire source, so it is
-- expensive on a large table or a rate-limited API.
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR;


------------------------------------------------------------------
-- 2. Bounded by date range
------------------------------------------------------------------
-- Far cheaper. Appropriate for frequent scheduled reconciliation.
-- Trade-off: a row deleted outside the window is not detected, so
-- pair this with an occasional full run.
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR
START DATEADD(DAY, -3, CURRENT_DATE())
END CURRENT_DATE();


------------------------------------------------------------------
-- 3. Deletes only  <- the one I reach for most
------------------------------------------------------------------
-- SKIP MODIFIED reconciles deletions without re-checking every
-- modified value. This is the efficient answer when incremental
-- replication already handles inserts and updates correctly and
-- deletes are the only gap.
CHECKCACHE Customers
AGAINST [public].[customers]
WITH REPAIR
SKIP MODIFIED
START LAST_MONTH();


------------------------------------------------------------------
-- 4. Narrowed to specific columns
------------------------------------------------------------------
-- Comparing a subset is much cheaper than comparing a wide table.
-- Use when only a few columns matter, or when you want to detect
-- presence and absence rather than value drift.
CHECKCACHE Customers
AGAINST (SELECT Id, Name, ModifiedDate FROM [public].[customers])
WITH REPAIR
START '2026-01-01'
END '2026-06-01';


------------------------------------------------------------------
-- Operating notes
------------------------------------------------------------------
-- - Put reconciliation in its OWN job, not the replication job.
--   Different schedule, different runtime, and a reconciliation
--   failure should not mark your replication job red.
--
-- - Schedule off-peak. It reads the whole source within the window
--   and will compete with your replication jobs for the same
--   connection budget.
--
-- - Alert on it. A run that repaired an unusually large number of
--   rows is a signal that something upstream is wrong.
--
-- - It is a repair tool, not a design. Constantly repairing large
--   numbers of rows means the incremental configuration is wrong:
--   usually a bad check column, a timezone offset, or a primary key
--   that does not uniquely identify rows.
