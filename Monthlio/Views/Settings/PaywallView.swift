import SwiftUI

/// One-time purchase sheet for Monthlio Pro.
struct PaywallView: View {
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    /// Runs after a successful purchase or restore, before dismissing.
    var onUnlocked: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 10) {
                        Image(systemName: "icloud.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                            .padding(.top, 24)
                        Text("Monthlio Pro")
                            .font(.title.bold())
                        Text("Keep every device in step.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        benefit("icloud", title: "iCloud sync", detail: "Your expenses, budgets and history on every iPhone and iPad signed in to your Apple Account.")
                        benefit("lock.shield", title: "Private by design", detail: "Data syncs through your own iCloud. Monthlio has no servers and no accounts.")
                        benefit("infinity", title: "Buy once, keep forever", detail: "One purchase, no subscription. Supports an independent app.")
                    }
                    .padding(20)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

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
                        .disabled(pro.isPurchasing)

                        if let error = pro.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }

                    Link("Privacy Policy", destination: URL(string: "https://github.com/brandonmogs/monthlio/blob/main/PRIVACY.md")!)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .readableWidth()
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if pro.product == nil { await pro.loadProduct() }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func benefit(_ symbol: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buy() async {
        if pro.product == nil {
            await pro.loadProduct()
            return
        }
        if await pro.purchase() {
            Haptics.success()
            onUnlocked()
            dismiss()
        }
    }

    private func restore() async {
        await pro.restore()
        if pro.isEntitled {
            Haptics.success()
            onUnlocked()
            dismiss()
        }
    }
}

#Preview {
    PaywallView()
        .environment(ProStore(defaults: UserDefaults(suiteName: "preview")!))
}
