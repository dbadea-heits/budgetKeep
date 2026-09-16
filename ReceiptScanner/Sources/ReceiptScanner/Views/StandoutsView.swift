import SwiftUI
import SwiftData

/// Shows rarely-purchased items (bought ≤2 times).
struct StandoutsView: View {
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    /// Computed standouts: items purchased ≤2 times.
    private var standouts: [StandoutItem] {
        var frequency: [String: (count: Int, lastDate: Date, totalSpent: Decimal)] = [:]

        for receipt in receipts {
            for item in receipt.lineItems {
                let key = item.productName.lowercased().trimmingCharacters(in: .whitespaces)
                if key.isEmpty { continue }
                var entry = frequency[key] ?? (count: 0, lastDate: receipt.date, totalSpent: 0)
                entry.count += 1
                entry.totalSpent += item.price
                if receipt.date > entry.lastDate {
                    entry.lastDate = receipt.date
                }
                frequency[key] = entry
            }
        }

        return frequency
            .filter { $0.value.count <= 2 }
            .map { key, info in
                // Find a representative product name (use original casing from most recent)
                let originalName = findOriginalName(for: key)
                return StandoutItem(
                    productName: originalName,
                    purchaseCount: info.count,
                    lastPurchaseDate: info.lastDate,
                    totalSpent: info.totalSpent
                )
            }
            .sorted { $0.lastPurchaseDate > $1.lastPurchaseDate }
    }

    var body: some View {
        NavigationStack {
            Group {
                if standouts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 12),
                                GridItem(.flexible(), spacing: 12)
                            ],
                            spacing: 12
                        ) {
                            ForEach(standouts) { item in
                                StandoutCardView(item: item)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Produse Rare")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nicio achiziție rară", systemImage: "star.slash")
        } description: {
            Text("Produsele cumpărate de 1-2 ori vor apărea aici. Scanează mai multe bonuri pentru a descoperi ce ai cumpărat rar.")
        }
    }

    /// Find the original casing of a product name from the receipts.
    private func findOriginalName(for lowercasedKey: String) -> String {
        for receipt in receipts {
            for item in receipt.lineItems {
                let key = item.productName.lowercased().trimmingCharacters(in: .whitespaces)
                if key == lowercasedKey {
                    return item.productName
                }
            }
        }
        return lowercasedKey
    }
}

/// A single standout item for display.
struct StandoutItem: Identifiable {
    let id = UUID()
    let productName: String
    let purchaseCount: Int
    let lastPurchaseDate: Date
    let totalSpent: Decimal
}

/// Card view for a single standout item.
struct StandoutCardView: View {
    let item: StandoutItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Product name
            Text(item.productName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            // Purchase count badge
            HStack(spacing: 4) {
                Image(systemName: "cart.badge.questionmark")
                    .font(.caption)
                Text("×\(item.purchaseCount)")
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

            // Last purchase date
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text(item.lastPurchaseDate, style: .date)
                    .font(.caption2)
            }
            .foregroundColor(.secondary)

            // Total spent
            HStack(spacing: 4) {
                Image(systemName: "creditcard")
                    .font(.caption2)
                Text(Formatting.price(item.totalSpent))
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}
