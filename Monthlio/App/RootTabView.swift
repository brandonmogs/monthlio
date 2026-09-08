import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.pie.fill")
                }

            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet.rectangle.fill")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(PreviewContainer.shared)
}
