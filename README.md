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
| **الأصناف والأسعار** | While he types an item name, the app suggests items from past orders and fills in the last unit and price (last sale price for sales, last purchase price for purchases). Once a client or supplier is chosen, their own last price for the item comes first and is the one filled in. Under each item: that party's last price and the general last buy and sell prices, with a red warning if a sale price is below the last purchase price. Item suggestions and search ignore common Arabic spelling differences (أ/ا, ة/ه, ى/ي). A screen lists every item with its last prices. |
| **المخزون** | Stock per item = purchases − sales + stock counts (جرد). He enters an opening count once per item with "صنف جديد", or taps an item to count it later. Only counted items show stock, so years of old history don't produce false alarms. Optional low-stock level per item, a home-screen alert, and a warning in the order form when a sale exceeds what's in stock. |
| **المصروفات** | Business costs by month (transport, loading, rent, electricity, wages, maintenance, other) with a monthly total. They feed the monthly profit. |
| **الربح والتقرير الشهري** | Estimated profit on every sale = (sale price − average purchase price) × quantity, for items with a known purchase price; lines without one are flagged instead of counted as pure profit. A monthly report (sales, purchases, collections, payments to suppliers, expenses, gross and net profit, top clients and items) can be shared as a PDF. |
| **حاسبة الوزن** | On any order line: pick the metal and shape (plate, flat bar, round bar/rebar, pipe, tube, angle), enter dimensions, length and pieces, and the weight fills the quantity in kilos or tons, so he can price per kilo. |
| **الشيكات** | Cheques received or written, with due dates. They don't affect balances until marked "تم الصرف", which records the payment; a bounced cheque removes it again. The home screen warns about cheques due within 7 days. |
| **صور الطلبات** | Photos on any order (equipment condition, delivery receipts) from the camera or gallery, with a zoomable viewer. Backed up to Drive with the voice notes. |
| **كشف حساب** | Per client/supplier: every order and payment with a running balance (عليه / له), record payments on account, send the statement on WhatsApp |
| **التحصيل** | Everyone who owes us, biggest first, with the time since they last paid, a "متأخر" (overdue) flag after 30 days without payment, a one-tap polite WhatsApp reminder, and when they were last reminded |
| **العملاء** | Clients and suppliers (or both), search by name or phone, one-tap call or WhatsApp, balance, full order history |
| **ملاحظات صوتية** | Record or play voice notes on a client/supplier, optionally linked to a specific order |
| **نسخ احتياطي واستعادة** | Every day after 21:00 the app updates an Excel file (`دفتر المعدات - البيانات.xlsx`) and a full database copy in a Drive folder, and uploads any new voice notes. Drive keeps older versions. A new phone can restore everything from Settings. |

## Tech

Flutter, Riverpod 3, go_router, drift (SQLite), record + audioplayers,
image_picker, Google Sign-In 7 + Drive API v3 (`drive.file` scope only),
workmanager, excel, pdf + printing.

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

## Testing

```bash
flutter test                                          # everything
flutter test --test-randomize-ordering-seed random     # catches tests that depend on each other
flutter test test/stress_test.dart                     # 5,000 orders: correctness + speed
```

`stress_test.dart` builds a random but repeatable data set (500 parties, 5,000 orders, 3,000 payments). It checks every balance, statement, stock level, last price and monthly profit against an independent calculation in plain Dart, and fails if a main query exceeds its time budget. It found the missing indexes that made the home screen take 6 s; it now takes about 25 ms.

PDF layout was checked by rendering pages to images (`PDF_OUT=<dir> flutter test test/order_pdf_test.dart`).

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
