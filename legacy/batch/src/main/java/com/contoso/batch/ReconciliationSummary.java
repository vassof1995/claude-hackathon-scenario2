package com.contoso.batch;

import java.time.LocalDate;

/** Result of a single reconciliation run, returned by POST /run. */
public record ReconciliationSummary(
        LocalDate businessDate,
        int transactionsProcessed,
        int accountsReconciled,
        int discrepanciesFound) {
}
