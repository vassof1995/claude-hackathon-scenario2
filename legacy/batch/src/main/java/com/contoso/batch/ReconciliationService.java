package com.contoso.batch;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Nightly reconciliation. For a business date it:
 *   1. reads that day's transactions from the app schema,
 *   2. compares each against a mocked external ledger feed,
 *   3. computes per-account opening/closing balances,
 *   4. writes daily_balances, reconciliation_results and discrepancies.
 *
 * Idempotent per business date: re-running replaces that date's reporting rows.
 */
@Service
public class ReconciliationService {

    private final JdbcTemplate jdbc;

    public ReconciliationService(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    /** A single transaction as read from the app schema. */
    private record Txn(long id, long accountId, BigDecimal amount, String direction, String externalRef) {
        /** Signed contribution to the balance: CREDIT adds, DEBIT subtracts. */
        BigDecimal signed() {
            return "CREDIT".equals(direction) ? amount : amount.negate();
        }
    }

    @Transactional
    public ReconciliationSummary reconcile(LocalDate businessDate) {
        // 1. idempotency: clear any prior output for this date
        jdbc.update("DELETE FROM reporting.discrepancies WHERE business_date = ?", businessDate);
        jdbc.update("DELETE FROM reporting.reconciliation_results WHERE business_date = ?", businessDate);
        jdbc.update("DELETE FROM reporting.daily_balances WHERE business_date = ?", businessDate);

        // 2. read the day's transactions
        List<Txn> dayTxns = jdbc.query(
                "SELECT id, account_id, amount, direction, external_ref " +
                        "FROM app.transactions WHERE booked_at::date = ? ORDER BY account_id, id",
                (rs, i) -> new Txn(rs.getLong("id"), rs.getLong("account_id"),
                        rs.getBigDecimal("amount"), rs.getString("direction"),
                        rs.getString("external_ref")),
                businessDate);

        // group by account, preserving order
        Map<Long, List<Txn>> byAccount = new LinkedHashMap<>();
        for (Txn t : dayTxns) {
            byAccount.computeIfAbsent(t.accountId(), k -> new ArrayList<>()).add(t);
        }

        int totalDiscrepancies = 0;
        for (Map.Entry<Long, List<Txn>> entry : byAccount.entrySet()) {
            long accountId = entry.getKey();
            List<Txn> txns = entry.getValue();

            BigDecimal opening = openingBalance(accountId, businessDate);
            BigDecimal daySum = txns.stream().map(Txn::signed).reduce(BigDecimal.ZERO, BigDecimal::add);
            BigDecimal closing = opening.add(daySum);

            int matched = 0;
            int unmatched = 0;
            for (Txn t : txns) {
                BigDecimal expected = expectedFromLedger(t);
                if (expected.compareTo(t.amount()) == 0) {
                    matched++;
                } else {
                    unmatched++;
                    jdbc.update("INSERT INTO reporting.discrepancies " +
                                    "(business_date, account_id, transaction_ref, expected_amount, actual_amount, reason) " +
                                    "VALUES (?, ?, ?, ?, ?, ?)",
                            businessDate, accountId, t.externalRef(), expected, t.amount(),
                            "Amount mismatch against external ledger");
                }
            }
            totalDiscrepancies += unmatched;

            jdbc.update("INSERT INTO reporting.daily_balances " +
                            "(account_id, business_date, opening_balance, closing_balance) VALUES (?, ?, ?, ?)",
                    accountId, businessDate, opening, closing);

            jdbc.update("INSERT INTO reporting.reconciliation_results " +
                            "(business_date, account_id, transactions_count, total_amount, matched_count, unmatched_count, status) " +
                            "VALUES (?, ?, ?, ?, ?, ?, ?)",
                    businessDate, accountId, txns.size(), daySum, matched, unmatched,
                    unmatched == 0 ? "OK" : "DISCREPANCIES_FOUND");
        }

        return new ReconciliationSummary(businessDate, dayTxns.size(), byAccount.size(), totalDiscrepancies);
    }

    private BigDecimal openingBalance(long accountId, LocalDate businessDate) {
        BigDecimal opening = jdbc.queryForObject(
                "SELECT COALESCE(SUM(CASE WHEN direction = 'CREDIT' THEN amount ELSE -amount END), 0) " +
                        "FROM app.transactions WHERE account_id = ? AND booked_at::date < ?",
                BigDecimal.class, accountId, businessDate);
        return opening == null ? BigDecimal.ZERO : opening;
    }

    /**
     * Mocked external settlement/ledger feed. For most transactions the ledger agrees
     * with what we booked; for a deterministic, seeded subset it differs, so the
     * reconciliation output is non-trivial. (id % 7 == 0 -> ledger is 10.00 lower.)
     */
    private BigDecimal expectedFromLedger(Txn t) {
        if (t.id() % 7 == 0) {
            return t.amount().subtract(new BigDecimal("10.00"));
        }
        return t.amount();
    }
}
