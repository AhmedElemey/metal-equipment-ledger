# Business Analysis — دفتر المعدات

## 1. The business today

The owner trades metal equipment, buying from suppliers and selling to clients.
The questions that matter most every day:

1. **Who owes me money, and how much?** Selling on credit (آجل) is normal in Egyptian trading.
2. **Who do I owe?**
3. **What did this client buy before, and at what price?** This is what he relies on when negotiating.
4. **What did we agree on?** Agreements are often spoken (by phone or in person), which is why voice notes matter.

v1 answers all four. Below are the features recommended next, ranked by value
to him versus effort.

## 2. Recommended features

### Phase 2 — high value, low effort (next 2–4 weeks)

| # | Feature | Why it matters for him |
|---|---|---|
| 1 | ✅ **Payments ledger (كشف حساب)** — done in v1.1: each payment is its own dated entry; print/share a client statement | Today "paid" is one number per order. A real statement ("on 3/10 he paid 5,000") ends disputes, and he can send it on WhatsApp. |
| 2 | ✅ **Payment reminders** — done in v1.1: list of clients with overdue balances (e.g. > 30 days), one tap sends a polite WhatsApp reminder | Turns the receivables number into cash collected. |
| 3 | ✅ **PDF invoice / quotation (عرض سعر)** — done in v1.2 (no logo yet), shared via WhatsApp or any app | Looks professional. A quotation can be converted into an order with one tap. |
| 4 | ✅ **Restore from Drive** — done in v1.3 (voice notes included) | v1 already uploads the full DB. Restore protects him if the phone is lost or replaced. |
| 5 | ✅ **Item catalog with last price** — done in v1.4: when typing an item name, suggest it and show the last buy and sell price | Faster order entry, and he never sells below what he paid. |

### Phase 3 — medium effort

| # | Feature | Why |
|---|---|---|
| 6 | ✅ **Stock (المخزون)** — done in v1.5: quantities go up on purchase and down on sale, with a low-stock alert | Knows what he has before promising a client. |
| 7 | **Profit per order and per month** (sell price − purchase cost) | Shows which items and clients actually make money. |
| 8 | **Monthly report** (sales, purchases, collections, top clients/items) shared as PDF | End-of-month review without spreadsheets. |
| 9 | ✅ **Expenses** — done in v1.6 (transport, loading, workshop rent) | Profit then reflects real costs. |
| 10 | **Weight-based pricing**: price per kg/ton, with the weight computed from dimensions for sheets, pipes and angles | Very common in metal trading, and it removes calculator errors. |

### Phase 4 — when the business grows

| # | Feature | Why |
|---|---|---|
| 11 | **Multi-user** (owner + employee) with a cloud database (e.g. Firebase/Supabase) and roles (the employee can't see profit) | Once someone else takes orders. |
| 12 | **Photos of equipment / delivery receipts** attached to orders | Proof of delivery and condition, useful for used equipment. |
| 13 | **Cheques (شيكات) tracking** with due-date alerts | Common for larger B2B deals. |
| 14 | **Voice-to-text** for voice notes, so they can be searched | Find "the client who wanted 2 mm sheet" months later. |

## 3. What I deliberately left out of v1

- **Login / accounts**: one owner, one phone, so data stays on the device and is backed up to Drive.
- **Server backend**: not needed until there is more than one user (see #11). It would add monthly cost and failure points.
- **English UI**: the owner works in Arabic only.

## 4. Success metrics to watch

- Total receivables trending **down** month over month (collections working).
- Every order has a client and items (no "loose" orders on paper).
- The backup "last backup" date is never older than 1 day.
