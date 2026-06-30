package com.contoso.batch;

import java.time.LocalDate;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** Triggers the nightly reconciliation on the configured cron (recon.cron). */
@Component
public class ReconciliationScheduler {

    private static final Logger log = LoggerFactory.getLogger(ReconciliationScheduler.class);

    private final ReconciliationService service;

    public ReconciliationScheduler(ReconciliationService service) {
        this.service = service;
    }

    @Scheduled(cron = "${recon.cron}")
    public void runNightly() {
        LocalDate businessDate = LocalDate.now().minusDays(1);
        log.info("Nightly reconciliation starting for business date {}", businessDate);
        ReconciliationSummary summary = service.reconcile(businessDate);
        log.info("Nightly reconciliation finished: {}", summary);
    }
}
