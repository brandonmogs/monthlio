# Monthlio

A lightweight, offline-first monthly expense tracker for iOS. Enter your
expenses at whatever cadence they bill and see your true monthly cost broken
down by category.

- Swift 5 / SwiftUI / iOS 17+
- SwiftData for persistence, Swift Charts for the donut
- No third-party dependencies

## Build & run

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated and not committed.

```sh
xcodegen generate
xcodebuild -scheme Monthlio -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild test -scheme Monthlio -destination 'platform=iOS Simulator,name=iPhone 15'
```

Or open `Monthlio.xcodeproj` after generating and press Run.

DEBUG builds seed a realistic set of expenses, income, budgets and eight
months of history on first launch. Launch arguments (DEBUG only):

- `-MonthlioSkipSeed` — start empty to see the first-run state
- `-MonthlioTab upcoming` — open on a tab (`dashboard`, `expenses`, `subscriptions`, `upcoming`)

## Layout

```
Monthlio/
  App/          entry point + tab root
  Models/       Expense, AppSettings, CategoryBudget, MonthSnapshot, enums
  ViewModels/   dashboard selection, form state, list search/sort
  Views/        Dashboard/, Expenses/, Subscriptions/, Upcoming/, Settings/, Shared/
  Services/     ExpenseCalculator, SnapshotService, BudgetEvaluator,
                UpcomingChargeCalculator, NotificationScheduler, CSVExporter
  Utilities/    currency + decimal helpers, preview container
MonthlioTests/  35 tests over the calculators and exporter
```
