-- REPLICATE query patterns: primary keys, composite keys,
-- and explicit destination data types.
--
-- See docs/06-replication-queries.md


------------------------------------------------------------------
-- Table-level primary key — use this by default
------------------------------------------------------------------
-- Reads unambiguously and supports composite keys.
REPLICATE [CustomerData]
(
    CustomerRef VARCHAR(50),
    Email       VARCHAR(320),
    Phone       VARCHAR(50),
    PRIMARY KEY (CustomerRef)
)
SELECT CustomerRef, Email, Phone
FROM dbo.Customer;


------------------------------------------------------------------
-- Inline primary key — SINGLE COLUMN ONLY
------------------------------------------------------------------
REPLICATE [CustomerData]
(
    CustomerRef VARCHAR(50) PRIMARY KEY,
    Email       VARCHAR(320),
    Phone       VARCHAR(50)
)
SELECT CustomerRef, Email, Phone
FROM dbo.Customer;

-- WRONG. Marking two columns inline does NOT produce a composite key.
--
--   REPLICATE [CustomerData]
--   (
--       CustomerRef VARCHAR(50)  PRIMARY KEY,
--       Email       VARCHAR(320) PRIMARY KEY,   -- <-- not a composite key
--       Phone       VARCHAR(50)
--   )
--
-- Use the table-level form for anything with more than one column.


------------------------------------------------------------------
-- Composite primary key
------------------------------------------------------------------
-- Name every column that forms the row's identity. Getting this
-- wrong produces duplicates rather than an error, and adding a
-- column to the key later means rebuilding the table.
REPLICATE [AccountBalance]
(
    AccountNo  VARCHAR(50),
    BookId     VARCHAR(50),
    PeriodCode VARCHAR(20),
    Balance    DECIMAL(18,2),
    PRIMARY KEY (AccountNo, BookId, PeriodCode)
)
SELECT AccountNo, BookId, PeriodCode, Balance
FROM dbo.LedgerBalance;


------------------------------------------------------------------
-- Explicit destination data types
------------------------------------------------------------------
-- Override what the source reports. Do this BEFORE the first load;
-- changing a column type afterwards means a rebuild.
--
--   - DECIMAL with explicit precision for money, never float
--   - Native UUID rather than VARCHAR(36)
--   - DATE where there is no time component
--   - Size strings from sampled actual maximum length
REPLICATE [CustomerRecord]
(
    CustomerId  INT,
    ExternalRef UUID,
    RecordId    UUID,
    CreatedOn   DATE,
    Email       VARCHAR(320),
    Balance     DECIMAL(18,2),
    PRIMARY KEY (CustomerId, ExternalRef)
)
SELECT CustomerId, ExternalRef, RecordId, CreatedOn, Email, Balance
FROM dbo.SourceCustomers;


------------------------------------------------------------------
-- Composite key plus incremental filter plus batch control
------------------------------------------------------------------
REPLICATE [SessionSummary]
(
    ConversationId VARCHAR(100),
    ParticipantId  VARCHAR(100),
    SessionId      VARCHAR(100),
    ProcessedAt    DATETIME,
    PRIMARY KEY (ConversationId, ParticipantId, SessionId)
)
WITH BatchSize='10000', DropTable='false'
SELECT ConversationId, ParticipantId, SessionId, ProcessedAt
FROM SessionSummary
WHERE ProcessedAt >= REPLICATE_LASTMODTIME();
