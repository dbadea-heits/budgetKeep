import Foundation
import SwiftData

@Model
final class Receipt {
    @Attribute(.unique) var id: UUID
    var storeName: String
    var date: Date
    var currency: String
    var rawOcrText: String
    var imagePath: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LineItem.receipt)
    var lineItems: [LineItem]

    init(
        id: UUID = UUID(),
        storeName: String,
        date: Date,
        currency: String = "RON",
        rawOcrText: String = "",
        imagePath: String? = nil,
        createdAt: Date = Date(),
        lineItems: [LineItem] = []
    ) {
        self.id = id
        self.storeName = storeName
        self.date = date
        self.currency = currency
        self.rawOcrText = rawOcrText
        self.imagePath = imagePath
        self.createdAt = createdAt
        self.lineItems = lineItems
    }
}

// MARK: - Computed Properties

extension Receipt {
    var total: Decimal {
        lineItems.reduce(Decimal.zero) { $0 + $1.price }
    }

    var itemCount: Int {
        lineItems.count
    }

    var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy"
        return df.string(from: date)
    }

    var formattedDateTime: String {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy HH:mm"
        return df.string(from: date)
    }

    var formattedTotal: String {
        Formatting.price(total)
    }

    var itemsByCategory: [(Category, [LineItem])] {
        let grouped = Dictionary(grouping: lineItems) { $0.category }
        return Category.allCases.compactMap { cat in
            guard let items = grouped[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }
}

enum Formatting {
    static func price(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "RON"
        formatter.locale = Locale(identifier: "ro_RO")
        if let formatted = formatter.string(from: amount as NSDecimalNumber) {
            return formatted
        }
        return "\(amount) RON"
    }
}
