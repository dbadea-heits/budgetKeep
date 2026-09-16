import SwiftUI
import SwiftData

/// Spending breakdown by category — total, percentage, bar chart.
struct CategorySummaryView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    @State private var showThisMonthOnly = false

    private var filteredReceipts: [Receipt] {
        guard showThisMonthOnly else { return receipts }
        let now = Date()
        let thisMonth = Calendar.current.component(.month, from: now)
        let thisYear = Calendar.current.component(.year, from: now)
        return receipts.filter {
            Calendar.current.component(.month, from: $0.date) == thisMonth &&
            Calendar.current.component(.year, from: $0.date) == thisYear
        }
    }

    /// All line items from filtered receipts.
    private var allLineItems: [LineItem] {
        filteredReceipts.flatMap { $0.lineItems }
    }

    /// Total spend across all filtered receipts.
    private var totalSpend: Decimal {
        filteredReceipts.reduce(Decimal.zero) { $0 + $1.total }
    }

    /// Spending per category.
    private var categorySpend: [(Category, Decimal)] {
        let grouped = Dictionary(grouping: allLineItems) { $0.category }
        return Category.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            let total = items.reduce(Decimal.zero) { $0 + $1.price }
            return (cat, total)
        }
        .sorted { $0.1 > $1.1 }
    }

    var body: some View {
        NavigationStack {
            List {
                // Total spend card
                Section {
                    VStack(spacing: 12) {
                        Text("Total cheltuit")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(Formatting.price(totalSpend))
                            .font(.system(size: 40, weight: .bold))

                        Text("\(filteredReceipts.count) bonuri • \(allLineItems.count) produse")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                // Toggle for this month
                Section {
                    Toggle(isOn: $showThisMonthOnly) {
                        Label("Doar această lună", systemImage: "calendar")
                    }
                }

                // Category breakdown
                if categorySpend.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Nicio cheltuială",
                            systemImage: "chart.pie",
                            description: Text("Scanează bonuri pentru a vedea statistici.")
                        )
                    }
                } else {
                    Section("Defalcare pe categorii") {
                        ForEach(categorySpend, id: \.0) { category, total in
                            if totalSpend > 0 {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(category.icon)
                                            .font(.title3)
                                        Text(category.displayName)
                                            .fontWeight(.medium)
                                        Spacer()
                                        VStack(alignment: .trailing) {
                                            Text(Formatting.price(total))
                                                .fontWeight(.semibold)
                                            Text(String(format: "%.1f%%", categoryPercentage(total)))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    // Progress bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color(.systemGray5))
                                                .frame(height: 6)

                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(categoryColor(category))
                                                .frame(width: geo.size.width * categoryPercentage(total) / 100, height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categorii")
        }
    }

    private func categoryColor(_ category: Category) -> Color {
        // Parse hex color
        let hex = category.colorHex
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func categoryPercentage(_ total: Decimal) -> Double {
        guard totalSpend > 0 else { return 0 }
        return NSDecimalNumber(decimal: total)
            .dividing(by: NSDecimalNumber(decimal: totalSpend))
            .doubleValue * 100
    }
}
