# Monthlio

A lightweight, offline-first monthly expense tracker for iPhone and iPad.
Enter your expenses at whatever cadence they bill and see your true monthly
cost broken down by category.

- Swift 5 / SwiftUI / iOS 17+
- SwiftData for persistence, Swift Charts for the donut, WidgetKit for the
  Home Screen and Lock Screen widgets, StoreKit 2 for the Pro unlock
- No third-party dependencies, no servers, no accounts

## Features

- Dashboard with the monthly total, category donut, budgets, income and
  month-over-month history
- Expenses list with search and sort, subscriptions view with cancel
  toggles and price-increase flags, 30-day upcoming timeline with local
  reminders
- Face ID / Touch ID / passcode lock with a privacy shield in the app switcher
- Multi-currency with a base currency and manual rates
- Home Screen and Lock Screen widgets: next charge and monthly total
- JSON backup and restore, CSV export and CSV import
- iCloud sync (Monthlio Pro, a one-time purchase; free for installs from
  before Pro existed)
- English source strings in a String Catalog, ready for translation

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated and not committed.

```sh
xcodegen generate
xcodebuild -scheme Monthlio -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild test -scheme Monthlio -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or open `Monthlio.xcodeproj` after generating and press Run. The scheme
uses `StoreKit/Monthlio.storekit`, so the Pro purchase works in the
simulator without App Store Connect.

DEBUG builds seed a realistic set of expenses, income, budgets and eight
months of history on first launch. Launch arguments (DEBUG only):

- `-MonthlioSkipSeed` — start empty to see the first-run state
- `-MonthlioTab upcoming` — open on a tab (`dashboard`, `expenses`, `subscriptions`, `upcoming`)
- `-MonthlioLocked` — start with the Face ID / passcode lock engaged
- `-MonthlioSettings` — open Settings on launch
- `-MonthlioInMemory` — use a throwaway in-memory store (the UI tests do this)

The app also opens `monthlio://dashboard` and `monthlio://upcoming`, which
the widgets use as deep links.

## Localization

All user-facing strings live in `Monthlio/Resources/Localizable.xcstrings`
(and `InfoPlist.xcstrings` for the Face ID usage description). Xcode syncs
the catalog when you build in the IDE; `xcodebuild` only emits the
compiler's `.stringsdata`, so after a command-line build run

```sh
Scripts/sync-string-catalog.py <DerivedData> Monthlio/Resources/Localizable.xcstrings Monthlio
```

to add any new keys. Plurals use automatic grammar agreement
(`^[%lld expense](inflect: true)`), so translators add plural forms in the
catalog rather than in code.

## Shipping checklist

Things App Store Connect needs that the code can't do for you:

- **Monthlio Pro**: create a non-consumable in-app purchase with product ID
  `com.monthlio.app.pro`, and sign the Paid Applications agreement.
- **App Group**: automatic signing registers `group.com.monthlio.app` for
  the app and the widget; check it appears on both bundle IDs in the
  developer portal if a device build fails to sign.
- **CloudKit**: deploy schema changes to Production in CloudKit Console
  before submitting a build that adds fields (current fields include
  `chargeDate` on expenses and `baseCode` on exchange rates).
- **iPad**: the app now targets iPad, so the listing needs iPad screenshots.

## Layout

```
Monthlio/
  App/          entry point + tab root
  Models/       Expense, AppSettings, CategoryBudget, MonthSnapshot, ExchangeRate, enums
  ViewModels/   dashboard selection, form state, list search/sort
  Views/        Dashboard/, Expenses/, Subscriptions/, Upcoming/, Settings/, Shared/
  Services/     ExpenseCalculator, CurrencyConverter/Store, AppLockService,
                SnapshotService, BudgetEvaluator, UpcomingChargeCalculator,
                NotificationScheduler, CSVExporter/Importer, BackupService,
                WidgetSnapshotWriter, ProStore, SyncPreference
  Widgets/      snapshot model, timeline builder and views shared with the extension
  Utilities/    currency + decimal helpers, preview container
  Resources/    asset catalog, String Catalogs
MonthlioWidget/ WidgetKit extension (bundle, provider)
MonthlioTests/  unit tests over the calculators, converter, lock, exporter,
                importer, backup, widgets and Pro
Scripts/        string catalog sync
StoreKit/       local StoreKit configuration for testing purchases
```
