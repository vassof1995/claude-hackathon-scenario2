package com.contoso.batch;

import java.time.LocalDate;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Manual trigger for the reconciliation job, for testing and ops re-runs.
 *   POST /run            -> reconciles yesterday
 *   POST /run?date=YYYY-MM-DD -> reconciles the given business date
 */
@RestController
public class ReconciliationController {

    private final ReconciliationService service;

    public ReconciliationController(ReconciliationService service) {
        this.service = service;
    }

    @PostMapping("/run")
    public ReconciliationSummary run(
            @RequestParam(required = false)
            @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate date) {
        LocalDate businessDate = (date != null) ? date : LocalDate.now().minusDays(1);
        return service.reconcile(businessDate);
    }
}
