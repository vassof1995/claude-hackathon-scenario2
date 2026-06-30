-- Reporting schema: the reconciliation job's output.
-- Owned by batch_user (set via Flyway default-schema=reporting).
-- report_reader gets automatic SELECT on these tables (default privileges set at bootstrap),
-- which is what the five reporting teams query.

CREATE TABLE reporting.daily_balances (
    id              BIGSERIAL PRIMARY KEY,
    account_id      BIGINT        NOT NULL,
    business_date   DATE          NOT NULL,
    opening_balance NUMERIC(15,2) NOT NULL,
    closing_balance NUMERIC(15,2) NOT NULL,
    computed_at     TIMESTAMP     NOT NULL DEFAULT now(),
    UNIQUE (account_id, business_date)
);

CREATE TABLE reporting.reconciliation_results (
    id                 BIGSERIAL PRIMARY KEY,
    business_date      DATE          NOT NULL,
    account_id         BIGINT        NOT NULL,
    transactions_count INTEGER       NOT NULL,
    total_amount       NUMERIC(15,2) NOT NULL,
    matched_count      INTEGER       NOT NULL,
    unmatched_count    INTEGER       NOT NULL,
    status             VARCHAR(32)   NOT NULL,
    computed_at        TIMESTAMP     NOT NULL DEFAULT now(),
    UNIQUE (account_id, business_date)
);

CREATE TABLE reporting.discrepancies (
    id              BIGSERIAL PRIMARY KEY,
    business_date   DATE          NOT NULL,
    account_id      BIGINT        NOT NULL,
    transaction_ref VARCHAR(64)   NOT NULL,
    expected_amount NUMERIC(15,2) NOT NULL,
    actual_amount   NUMERIC(15,2) NOT NULL,
    reason          VARCHAR(200)  NOT NULL,
    detected_at     TIMESTAMP     NOT NULL DEFAULT now()
);

CREATE INDEX idx_daily_balances_date ON reporting.daily_balances (business_date);
CREATE INDEX idx_recon_results_date  ON reporting.reconciliation_results (business_date);
CREATE INDEX idx_discrepancies_date  ON reporting.discrepancies (business_date);
