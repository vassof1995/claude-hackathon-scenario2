<script setup>
import { ref, onMounted } from 'vue'

const customers = ref([])
const accounts = ref([])
const transactions = ref([])
const selectedCustomer = ref(null)
const selectedAccount = ref(null)
const error = ref(null)

async function get(url) {
  const res = await fetch(url)
  if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
  return res.json()
}

async function loadCustomers() {
  try {
    customers.value = await get('/api/customers')
  } catch (e) {
    error.value = `Could not load customers: ${e.message}`
  }
}

async function selectCustomer(c) {
  selectedCustomer.value = c
  selectedAccount.value = null
  transactions.value = []
  accounts.value = await get(`/api/customers/${c.id}/accounts`)
}

async function selectAccount(a) {
  selectedAccount.value = a
  transactions.value = await get(`/api/accounts/${a.id}/transactions`)
}

function money(v, ccy) {
  return `${Number(v).toFixed(2)} ${ccy || ''}`.trim()
}

onMounted(loadCustomers)
</script>

<template>
  <main>
    <header>
      <h1>Contoso Financial</h1>
      <p class="sub">Customer self-service portal</p>
    </header>

    <p v-if="error" class="error">{{ error }}</p>

    <div class="cols">
      <section>
        <h2>Customers</h2>
        <ul>
          <li
            v-for="c in customers"
            :key="c.id"
            :class="{ active: selectedCustomer && selectedCustomer.id === c.id }"
            @click="selectCustomer(c)"
          >
            {{ c.name }}<br /><small>{{ c.email }}</small>
          </li>
        </ul>
      </section>

      <section v-if="selectedCustomer">
        <h2>Accounts</h2>
        <ul>
          <li
            v-for="a in accounts"
            :key="a.id"
            :class="{ active: selectedAccount && selectedAccount.id === a.id }"
            @click="selectAccount(a)"
          >
            {{ a.iban }}<br /><small>Balance: {{ money(a.balance, a.currency) }}</small>
          </li>
        </ul>
      </section>

      <section v-if="selectedAccount">
        <h2>Transactions</h2>
        <table v-if="transactions.length">
          <thead>
            <tr><th>Date</th><th>Ref</th><th>Direction</th><th class="r">Amount</th></tr>
          </thead>
          <tbody>
            <tr v-for="t in transactions" :key="t.id">
              <td>{{ (t.bookedAt || '').replace('T', ' ').slice(0, 16) }}</td>
              <td>{{ t.externalRef }}</td>
              <td>{{ t.direction }}</td>
              <td class="r">{{ money(t.amount) }}</td>
            </tr>
          </tbody>
        </table>
        <p v-else>No transactions.</p>
      </section>
    </div>
  </main>
</template>

<style>
body { margin: 0; font-family: system-ui, sans-serif; color: #1a2233; background: #f5f7fa; }
main { max-width: 1100px; margin: 0 auto; padding: 1.5rem; }
header h1 { margin: 0; color: #0b3d91; }
.sub { color: #66748c; margin-top: .25rem; }
.cols { display: grid; grid-template-columns: 1fr 1fr 1.4fr; gap: 1rem; margin-top: 1.5rem; }
section { background: #fff; border: 1px solid #e1e6ee; border-radius: 8px; padding: 1rem; }
h2 { font-size: 1rem; margin-top: 0; color: #0b3d91; }
ul { list-style: none; margin: 0; padding: 0; }
li { padding: .6rem; border-radius: 6px; cursor: pointer; border: 1px solid transparent; }
li:hover { background: #eef3fb; }
li.active { background: #e3edfc; border-color: #b9d0f5; }
small { color: #66748c; }
table { width: 100%; border-collapse: collapse; font-size: .9rem; }
th, td { text-align: left; padding: .4rem .5rem; border-bottom: 1px solid #eef0f4; }
.r { text-align: right; }
.error { color: #b00020; background: #fde7ea; padding: .75rem; border-radius: 6px; }
</style>
