-- App schema: the customer-facing web app's data.
-- Owned by app_user (set via Flyway default-schema=app).

CREATE TABLE app.customers (
    id         BIGSERIAL PRIMARY KEY,
    name       VARCHAR(200) NOT NULL,
    email      VARCHAR(200) NOT NULL UNIQUE,
    created_at TIMESTAMP    NOT NULL DEFAULT now()
);

CREATE TABLE app.accounts (
    id          BIGSERIAL PRIMARY KEY,
    customer_id BIGINT        NOT NULL REFERENCES app.customers (id),
    iban        VARCHAR(34)   NOT NULL UNIQUE,
    currency    VARCHAR(3)    NOT NULL DEFAULT 'EUR',
    balance     NUMERIC(15,2) NOT NULL DEFAULT 0,
    opened_at   DATE          NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE app.transactions (
    id           BIGSERIAL PRIMARY KEY,
    account_id   BIGINT        NOT NULL REFERENCES app.accounts (id),
    amount       NUMERIC(15,2) NOT NULL,
    direction    VARCHAR(6)    NOT NULL CHECK (direction IN ('DEBIT', 'CREDIT')),
    booked_at    TIMESTAMP     NOT NULL DEFAULT now(),
    external_ref VARCHAR(64)   NOT NULL
);

CREATE INDEX idx_accounts_customer  ON app.accounts (customer_id);
CREATE INDEX idx_transactions_acct  ON app.transactions (account_id);
CREATE INDEX idx_transactions_date  ON app.transactions (booked_at);
