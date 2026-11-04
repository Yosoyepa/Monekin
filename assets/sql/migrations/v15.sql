-- ============================================================
-- v15 Migration: AI inbox and transaction attachments
--   * iInboxItems: transactions proposed by the AI that wait for review.
--   * 	ransactionAttachments: files (e.g. receipt photos) kept with a transaction.
--
-- Only two new tables are created. Nothing existing is touched.
-- ============================================================

CREATE TABLE IF NOT EXISTS aiInboxItems (
    id TEXT NOT NULL PRIMARY KEY,
    source TEXT NOT NULL CHECK(source IN ('receipt', 'statement', 'notification')),
    sourceRef TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'processed', 'discarded')),
    createdAt TEXT NOT NULL,
    proposalsJson TEXT NOT NULL,
    rawText TEXT,
    attachmentsJson TEXT,
    resultTransactionIdsJson TEXT,
    note TEXT
);

CREATE TABLE IF NOT EXISTS transactionAttachments (
    id TEXT NOT NULL PRIMARY KEY,
    transactionID TEXT NOT NULL REFERENCES transactions(id) ON DELETE CASCADE ON UPDATE CASCADE,
    filePath TEXT NOT NULL,
    createdAt TEXT NOT NULL
);