-- ============================================================
-- v16 Migration: claims of bank notices
--   * ai_notice_claims: fingerprints of the notices already taken in, so two readers of the
--     same notice (the live listener and the background scan) create one inbox item.
--
-- Only one new table is created. Nothing existing is touched.
-- ============================================================

CREATE TABLE IF NOT EXISTS ai_notice_claims (
    fingerprint TEXT NOT NULL PRIMARY KEY,
    createdAt TEXT NOT NULL
);
