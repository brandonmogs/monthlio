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
- JSON backup and restore, CSV import, and CSV export (Monthlio Pro)
- iCloud sync (Monthlio Pro, a one-time purchase; free on every device
  for anyone who downloaded Monthlio before Pro existed)
- Custom expense colors (Monthlio Pro), shown on every screen and in widgets
- A code from the developer unlocks Pro on that device: on the Pro page,
  tap the "Monthlio Pro" title five times or hold it for a second and a
  code field appears (VoiceOver: the "Enter a code" action). It is not
  advertised because App Review guideline 3.1.1 bars unlocking features
  with anything but in-app purchase. Accepted codes live as SHA-256
  digests in `ProStore.promoCodeDigests`
- Weekly, biweekly, quarterly and yearly charges on the timeline, in
  reminders and in the widget once they have a next charge date
- Undo after deleting an expense; a per-device app lock with a grace
  period; a reminder time of your choosing
- A lock-screen notification per expense: toggle it in the expense form,
  pick the date and time (the next charge is offered), and a recurring
  expense repeats it with its schedule
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

**Testing purchases:** on iOS 26.3 and later simulator runtimes the
StoreKit configuration only reaches the simulator when you run or test
from the Xcode IDE (Cmd+R / Cmd+U). From `xcodebuild` the paywall shows
"Try Again" instead of a price and the StoreKit integration test skips
itself. To see the purchase flow, run the app from Xcode, open Settings,
and tap the iCloud sync row. Apple tracks the command-line gap as
FB22237318.

DEBUG builds seed a realistic set of expenses, income, budgets and eight
months of history on first launch. Launch arguments (DEBUG only):

- `-MonthlioSkipSeed` — start empty to see the first-run state
- `-MonthlioTab upcoming` — open on a tab (`dashboard`, `expenses`, `subscriptions`, `upcoming`)
- `-MonthlioLocked` — start with the Face ID / passcode lock engaged
- `-MonthlioLockEnabled` — the lock is on but starts unlocked; `-MonthlioLockGrace <seconds>` sets its grace period (the lock round-trip UI tests)
- `-MonthlioSettings` — open Settings on launch
- `-MonthlioInMemory` — use a throwaway in-memory store and a throwaway preference store, and leave the widget snapshot and pending notifications alone (the UI tests do this)
- `-MonthlioFreshInstall` — a throwaway preference store with no grandfathering, so the paywall shows as it does for a new download
- `-MonthlioGrandfathered` — with `-MonthlioFreshInstall`: an install from before Pro existed (free iCloud sync, no Pro)

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

- **Privacy policy**: published at https://brandonmogs.github.io/monthlio-privacy/
  from the public `monthlio-privacy` repository; keep its `index.html` in
  step with `PRIVACY.md` here (the paywall link and the App Store Connect
  privacy URL both point there).
- **Support**: Settings > About and `SupportLinks.support` point at the
  issues page of that public repository, so Issues must be enabled on it
  (Settings > Features on GitHub), and the App Store listing's support
  URL should point there too instead of at this private repository.

- **Monthlio Pro**: create a non-consumable in-app purchase with product ID
  `com.monthlio.app.pro`, and get the Paid Apps Agreement to **Active**
  under Business > Agreements: confirm the legal entity, have the Account
  Holder accept the agreement, and add bank and tax details. While it is
  "New" or pending, the sandbox and App Review get an empty answer from
  `Product.products(for:)`, the paywall says "Monthlio Pro isn't available
  right now", and the review fails under guideline 2.1(b). The
  `Scripts/asc.py check` command prints a reminder because the API can't
  read the agreement. To see what App Review will see, run the app on a
  simulator without the local StoreKit configuration (the `MonthlioSandbox`
  scheme, or `xcrun simctl launch <udid> com.monthlio.app` on an installed
  build): StoreKit then asks Apple's sandbox catalog, and the app logs the
  answer under subsystem `com.monthlio.app`, category `store`
  (`xcrun simctl spawn <udid> log show --info --last 5m --predicate
  'subsystem == "com.monthlio.app" AND category == "store"'`). A newly
  activated agreement takes a while to reach that catalog.
- **App Group**: automatic signing registers `group.com.monthlio.app` for
  the app and the widget; check it appears on both bundle IDs in the
  developer portal if a device build fails to sign.
- **CloudKit**: the Production schema must contain every `CD_` record
  type and field before a build ships, or every sync export fails. Core
  Data creates the Development schema automatically when a Debug build
  runs on a device or simulator signed in to iCloud; after a model change
  run such a build once, confirm the new fields (1.4: `CD_colorHex` on
  `CD_Expense`; 1.5: `CD_reminderDate` on `CD_Expense` and
  `CD_currencyCode` on `CD_MonthSnapshot`) in CloudKit Console, and
  deploy Development to Production.
  As of 2026-10-05 the container had never had a schema in either
  environment, so this step is overdue, not routine.
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
