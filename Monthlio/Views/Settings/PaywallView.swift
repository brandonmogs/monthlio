import SwiftUI

/// Why the paywall is on screen. Opened for iCloud sync, an early
/// supporter whose sync is already free is let straight through; opened
/// as the Pro page (Settings, the color picker), everyone sees it, since
/// Pro also brings custom colors.
enum PaywallPurpose {
    case sync
    case pro
}

/// One-time purchase sheet for Monthlio Pro.
struct PaywallView: View {
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    var purpose: PaywallPurpose = .pro
    /// Runs after a successful purchase, restore or code, once sync has
    /// been turned on where it should be, before dismissing.
    var onUnlocked: () -> Void = {}

    var body: some View {
        NavigationStack {
            PaywallContent(purpose: purpose, onUnlocked: onUnlocked)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
                .task {
                    // The price loads while the App Store is asked which
                    // build this account downloaded; that check can show a
                    // sign-in prompt and take a while, and must not hold
                    // up the purchase button.
                    async let price: Void = pro.loadProduct()
                    await pro.recordOriginalBuildIfNeeded()
                    if purpose == .sync, pro.isGrandfathered {
                        pro.enableSyncAfterUnlock(purpose: purpose)
                        onUnlocked()
                        dismiss()
                    }
                    await price
                }
        }
        .presentationDragIndicator(.visible)
    }
}

/// The paywall's scrolling body, separate from the navigation chrome.
struct PaywallContent: View {
    var purpose: PaywallPurpose = .pro
    var onUnlocked: () -> Void = {}

    var body: some View {
        ScrollView {
            PaywallBody(purpose: purpose, onUnlocked: onUnlocked)
                .padding()
                .readableWidth()
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// The paywall's stack of pitch, benefits and buttons. Kept free of scroll
/// and navigation containers so ImageRenderer can draw it: the in-app
/// purchase review screenshot comes from a test that renders this view.
struct PaywallBody: View {
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    var purpose: PaywallPurpose = .pro
    var onUnlocked: () -> Void = {}
    @State private var showingCodeField = false
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                            .padding(.top, 24)
                            .accessibilityHidden(true)
                        Text("Monthlio Pro")
                            .font(.title.bold())
                            // Code entry is deliberately not advertised: App
                            // Review guideline 3.1.1 bars unlocking features
                            // with anything but in-app purchase, and a visible
                            // code field reads as exactly that. Five quick taps
                            // or a long press on the title reveal the field;
                            // VoiceOver gets it as a custom action.
                            .onTapGesture(count: 5) { revealCodeField() }
                            .onLongPressGesture(minimumDuration: 1.5) { revealCodeField() }
                            .accessibilityAction(named: Text("Enter a code")) { revealCodeField() }
                            .accessibilityIdentifier("paywall-title")
                        Text("Everything Monthlio can do, on every device you own.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if let product = pro.product {
                            Text("One-time purchase · \(product.displayPrice)")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .accessibilityLabel(Text("One-time purchase, \(product.displayPrice)"))
                        }
                    }

                    if purpose == .pro, pro.isGrandfathered, !pro.isEntitled {
                        Label {
                            Text("iCloud sync is already yours for free as an early supporter. Pro adds custom colors and CSV export, and supports the app.")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.pink)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("icloud", title: "iCloud sync", detail: "Your expenses, budgets, exchange rates and history on every iPhone and iPad signed in to your Apple Account. A new phone picks up right where you left off.")
                        benefit("paintpalette", title: "Custom colors", detail: "Give any expense its own color: on every screen, in every list and in your widgets.")
                        benefit("tablecells", title: "CSV export", detail: "Export every expense as a spreadsheet-ready CSV, with monthly equivalents in your base currency.")
                        benefit("person.2.fill", title: "Family Sharing", detail: "One purchase covers everyone in your Family Sharing group.")
                        benefit("lock.shield", title: "Private by design", detail: "Data syncs through your own iCloud. Monthlio has no servers, no accounts and no tracking.")
                        benefit("infinity", title: "Buy once, keep forever", detail: "One purchase, no subscription, no ads. Future Pro features are included, and it supports an independent app.")
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    Text("Everything else in Monthlio is free: expenses, budgets, the upcoming timeline, reminders, widgets, backups and import.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(spacing: 12) {
                        Button {
                            Task { await buy() }
                        } label: {
                            Group {
                                if pro.isEntitled {
                                    Label("Unlocked", systemImage: "checkmark")
                                } else if let product = pro.product {
                                    Text("Unlock for \(product.displayPrice)")
                                } else if pro.isLoadingProduct {
                                    ProgressView()
                                } else {
                                    Text("Try Again")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(pro.isPurchasing || pro.isEntitled || pro.isLoadingProduct)

                        Button("Restore Purchases") {
                            Task { await restore() }
                        }
                        .font(.subheadline)
                        .disabled(pro.isPurchasing || pro.isRestoring)

                        if !pro.isEntitled {
                            codeSection
                        }

                        if let error = pro.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Link("Privacy Policy", destination: SupportLinks.privacyPolicy)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
    }

    private func revealCodeField() {
        guard !showingCodeField else { return }
        withAnimation(Motion.animation(.snappy)) { showingCodeField = true }
        Haptics.selection()
    }

    /// A code from the developer unlocks Pro without a purchase. Shown
    /// only after the gesture on the title (see there for why).
    @ViewBuilder
    private var codeSection: some View {
        if showingCodeField {
            HStack(spacing: 10) {
                TextField("Code", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($codeFocused)
                    .onSubmit(redeemCode)
                    .onAppear { codeFocused = true }
                    .accessibilityIdentifier("paywall-code")
                Button("Redeem", action: redeemCode)
                    .buttonStyle(.bordered)
                    .disabled(ProStore.normalizedCode(code).isEmpty)
                    .accessibilityIdentifier("paywall-redeem")
            }
            .frame(maxWidth: 320)
        }
    }

    private func redeemCode() {
        guard pro.redeem(code: code) else {
            Haptics.warning()
            return
        }
        Haptics.success()
        pro.enableSyncAfterUnlock(purpose: purpose)
        onUnlocked()
        dismiss()
    }

    private func benefit(_ symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        // One VoiceOver stop per benefit, not three.
        .accessibilityElement(children: .combine)
    }

    private func buy() async {
        if pro.product == nil {
            await pro.loadProduct()
            return
        }
        if await pro.purchase() {
            Haptics.success()
            pro.enableSyncAfterUnlock(purpose: purpose)
            onUnlocked()
            dismiss()
        }
    }

    private func restore() async {
        await pro.restore()
        // Opened for sync, a free-sync account is done; opened as the Pro
        // page, only a found purchase closes it.
        if purpose == .sync ? pro.canSync : pro.isEntitled {
            Haptics.success()
            pro.enableSyncAfterUnlock(purpose: purpose)
            onUnlocked()
            dismiss()
        }
    }
}

#Preview {
    PaywallView()
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview")!))
}
