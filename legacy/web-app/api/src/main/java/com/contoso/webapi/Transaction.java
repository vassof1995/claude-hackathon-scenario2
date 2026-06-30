package com.contoso.webapi;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "transactions")
public class Transaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long accountId;
    private BigDecimal amount;
    private String direction;
    private LocalDateTime bookedAt;
    private String externalRef;

    public Long getId() { return id; }
    public Long getAccountId() { return accountId; }
    public BigDecimal getAmount() { return amount; }
    public String getDirection() { return direction; }
    public LocalDateTime getBookedAt() { return bookedAt; }
    public String getExternalRef() { return externalRef; }
}
