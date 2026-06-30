package com.contoso.webapi;

import java.util.List;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class CustomerController {

    private final CustomerRepository customers;
    private final AccountRepository accounts;
    private final TransactionRepository transactions;

    public CustomerController(CustomerRepository customers,
                              AccountRepository accounts,
                              TransactionRepository transactions) {
        this.customers = customers;
        this.accounts = accounts;
        this.transactions = transactions;
    }

    @GetMapping("/customers")
    public List<Customer> listCustomers() {
        return customers.findAll();
    }

    @GetMapping("/customers/{id}")
    public ResponseEntity<Customer> getCustomer(@PathVariable Long id) {
        return customers.findById(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping("/customers/{id}/accounts")
    public List<Account> customerAccounts(@PathVariable Long id) {
        return accounts.findByCustomerId(id);
    }

    @GetMapping("/accounts/{id}/transactions")
    public List<Transaction> accountTransactions(@PathVariable Long id) {
        return transactions.findByAccountIdOrderByBookedAtDesc(id);
    }
}
