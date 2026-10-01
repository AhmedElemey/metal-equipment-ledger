# دفتر المعدات (Metal Equipment Ledger)

An Arabic-only (RTL) Flutter app for a metal-equipment trading business. It tracks
sales to clients, purchases from suppliers, who owes what, and voice notes per
client or supplier. Everything is stored on the phone and works with no internet.
Every evening the data is backed up to Google Drive.

## Features (v1)

| Area | What it does |
|---|---|
| **الرئيسية** | Today's sales and purchases, what clients owe us, what we owe suppliers, open orders, latest orders |
| **طلباتي** | Sale and purchase orders with line items (qty × unit × price), status (جديد / قيد التنفيذ / تم التسليم / ملغي), optional down payment, dated payments per order, send the order to the client on WhatsApp |
| **فواتير وعروض أسعار PDF** | Any order can be shared as a PDF invoice (A4, Arabic, with the business name, phone and address set in Settings). A quotation (عرض سعر) is a sale that isn't counted in any balance until one tap converts it into a sale invoice dated today. |
| **الأصناف والأسعار** | While he types an item name, the app suggests items from past orders and fills in the last unit and price (last sale price for sales, last purchase price for purchases). Under each item: the last buy and sell prices, with a red warning if a sale price is below the last purchase price. Item suggestions and search ignore common Arabic spelling differences (أ/ا, ة/ه, ى/ي). A screen lists every item with its last prices. |
| **كشف حساب** | Per client/supplier: every order and payment with a running balance (عليه / له), record payments on account, send the statement on WhatsApp |
| **التحصيل** | Everyone who owes us, biggest first, with the time since they last paid, a "متأخر" (overdue) flag after 30 days without payment, a one-tap polite WhatsApp reminder, and when they were last reminded |
| **العملاء** | Clients and suppliers (or both), search by name or phone, one-tap call or WhatsApp, balance, full order history |
| **ملاحظات صوتية** | Record or play voice notes on a client/supplier, optionally linked to a specific order |
| **نسخ احتياطي واستعادة** | Every day after 21:00 the app updates an Excel file (`دفتر المعدات - البيانات.xlsx`) and a full database copy in a Drive folder, and uploads any new voice notes. Drive keeps older versions. A new phone can restore everything from Settings. |

## Tech

Flutter, Riverpod 3, go_router, drift (SQLite), record + audioplayers, Google
Sign-In 7 + Drive API v3 (`drive.file` scope only), workmanager, excel.

```
lib/
  core/            database (drift), router, theme, formatters, shared widgets
  features/
    dashboard/     home summary
    orders/        list, form, details
    parties/       clients & suppliers
    voice_notes/   recorder sheet, player, list
    backup/        Excel export, Drive upload, daily schedule, settings screen
```

Each party has **one net balance**: sales and payments we make add to it, purchases and payments we receive subtract from it. Positive means they owe us.
Payments are separate records (dated, optionally linked to an order), so the statement shows exactly when each payment was made.

Money is stored as integer piasters, which avoids rounding errors. Totals and
balances are computed in SQL, so they can never get out of sync with the line items.

## Run

```bash
flutter pub get
flutter run
flutter analyze && flutter test
# after changing tables in app_database.dart:
dart run build_runner build
```

## One-time Google Drive setup (needed for backup)

1. In [Google Cloud Console](https://console.cloud.google.com/), create a project and enable the **Google Drive API**.
2. Set up the **OAuth consent screen** (External). Add the owner's Gmail as a test user, or publish the app. `drive.file` is a non-sensitive scope, so Google does not need to verify the app.
3. Create an **OAuth client ID → Android** with package `com.ledger.metal_ledger` and the SHA-1 of your signing key (`cd android && ./gradlew signingReport`). Create one for the debug key and one for the release key.
4. In the app, open **الإعدادات → ربط حساب جوجل درايف**.

iOS: also create an iOS OAuth client and add `GIDClientID` and the reversed client
ID URL scheme to `Info.plist`. The daily background task is Android-only for now.
On iOS the backup runs when the app is opened after 21:00.

## Restore on a new phone

1. Install the app and open **الإعدادات → ربط حساب جوجل درايف**, using the **same Google account**.
2. Because the phone has no data, the app finds the latest backup and offers to restore it. You can also restore any time with **استعادة من جوجل درايف**. If the phone already has data, the app first shows a red warning listing what will be erased.

The restore checks the file first. A damaged backup, or one made by a newer app version, is refused, and the data on the phone is left untouched. Older backups are upgraded automatically. Voice notes are downloaded too.

The app **never uploads an empty database**, so a freshly installed phone can't overwrite the real backup. Once the new phone has data, backups go to the same Drive files. To get back an older day, use the file's **version history** in Drive (Drive keeps about 30 days).

## How the daily backup works

- WorkManager wakes the app every ~3 hours when the phone has internet. It
  uploads only if no backup has been made since the last 21:00, so you get one
  upload per day.
- Some phones (Xiaomi, Oppo, Realme…) kill background work. Because of that, the app
  also runs the same check every time it is opened. On those phones, set the app's
  battery setting to **No restrictions**.
