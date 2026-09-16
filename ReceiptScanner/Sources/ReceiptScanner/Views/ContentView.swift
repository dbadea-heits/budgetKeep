import SwiftUI

/// Main app view with tab-based navigation.
struct ContentView: View {
    var body: some View {
        TabView {
            ReceiptListView()
                .tabItem {
                    Label("Bonuri", systemImage: "receipt")
                }

            CategorySummaryView()
                .tabItem {
                    Label("Categorii", systemImage: "chart.pie")
                }

            StandoutsView()
                .tabItem {
                    Label("Rarități", systemImage: "star")
                }

            SettingsView()
                .tabItem {
                    Label("Setări", systemImage: "gear")
                }
        }
    }
}
