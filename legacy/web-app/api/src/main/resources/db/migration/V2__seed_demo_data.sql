-- Demo data so the web app shows content and the batch has something to reconcile.
-- All fake Contoso data, safe to share publicly.

INSERT INTO app.customers (id, name, email) OVERRIDING SYSTEM VALUE VALUES
    (1, 'Ada Lovelace',   'ada@contoso.example'),
    (2, 'Grace Hopper',   'grace@contoso.example'),
    (3, 'Alan Turing',    'alan@contoso.example');

INSERT INTO app.accounts (id, customer_id, iban, currency, balance, opened_at) OVERRIDING SYSTEM VALUE VALUES
    (1, 1, 'DE00100000000000000001', 'EUR', 0, CURRENT_DATE - 30),
    (2, 1, 'DE00100000000000000002', 'EUR', 0, CURRENT_DATE - 30),
    (3, 2, 'DE00100000000000000003', 'EUR', 0, CURRENT_DATE - 20),
    (4, 3, 'DE00100000000000000004', 'EUR', 0, CURRENT_DATE - 10);

-- Historical transactions (before the reconciliation date) -> opening balances.
INSERT INTO app.transactions (account_id, amount, direction, booked_at, external_ref) VALUES
    (1, 1000.00, 'CREDIT', (CURRENT_DATE - 3)::timestamp + time '09:00', 'SEED-OPEN-1'),
    (2,  500.00, 'CREDIT', (CURRENT_DATE - 3)::timestamp + time '09:05', 'SEED-OPEN-2'),
    (3, 2500.00, 'CREDIT', (CURRENT_DATE - 3)::timestamp + time '09:10', 'SEED-OPEN-3'),
    (4,  750.00, 'CREDIT', (CURRENT_DATE - 3)::timestamp + time '09:15', 'SEED-OPEN-4');

-- Transactions ON the reconciliation date (yesterday) -> reconciled by the batch.
INSERT INTO app.transactions (account_id, amount, direction, booked_at, external_ref) VALUES
    (1,  120.50, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '08:30', 'TXN-0001'),
    (1,  300.00, 'CREDIT', (CURRENT_DATE - 1)::timestamp + time '10:15', 'TXN-0002'),
    (1,   45.00, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '12:00', 'TXN-0003'),
    (2,   80.00, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '09:45', 'TXN-0004'),
    (2,  200.00, 'CREDIT', (CURRENT_DATE - 1)::timestamp + time '11:20', 'TXN-0005'),
    (2,   15.99, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '13:05', 'TXN-0006'),
    (3,  999.99, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '08:00', 'TXN-0007'),
    (3,  500.00, 'CREDIT', (CURRENT_DATE - 1)::timestamp + time '14:30', 'TXN-0008'),
    (3,   60.00, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '16:10', 'TXN-0009'),
    (4,  250.00, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '07:50', 'TXN-0010'),
    (4,  125.00, 'CREDIT', (CURRENT_DATE - 1)::timestamp + time '15:40', 'TXN-0011'),
    (4,   30.00, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '17:25', 'TXN-0012'),
    (1,   77.77, 'DEBIT',  (CURRENT_DATE - 1)::timestamp + time '18:00', 'TXN-0013'),
    (2,  410.00, 'CREDIT', (CURRENT_DATE - 1)::timestamp + time '18:30', 'TXN-0014');

-- Keep the BIGSERIAL sequences ahead of the explicit ids we inserted above.
SELECT setval('app.customers_id_seq', (SELECT max(id) FROM app.customers));
SELECT setval('app.accounts_id_seq',  (SELECT max(id) FROM app.accounts));
