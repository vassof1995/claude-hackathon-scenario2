package com.contoso.webapi;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.math.BigDecimal;
import java.time.LocalDate;

@Entity
@Table(name = "accounts")
public class Account {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    private Long customerId;
    private String iban;
    private String currency;
    private BigDecimal balance;
    private LocalDate openedAt;

    public Long getId() { return id; }
    public Long getCustomerId() { return customerId; }
    public String getIban() { return iban; }
    public String getCurrency() { return currency; }
    public BigDecimal getBalance() { return balance; }
    public LocalDate getOpenedAt() { return openedAt; }
}
