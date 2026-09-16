import SwiftUI
import SwiftData

@main
struct ReceiptScannerApp: App {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([Receipt.self, LineItem.self])
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                allowsSave: true
            )
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
