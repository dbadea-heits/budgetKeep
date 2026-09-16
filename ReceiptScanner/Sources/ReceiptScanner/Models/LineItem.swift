import Foundation
import SwiftData

@Model
final class LineItem {
    @Attribute(.unique) var id: UUID
    var productName: String
    var price: Decimal
    var category: Category

    var receipt: Receipt?

    init(
        id: UUID = UUID(),
        productName: String,
        price: Decimal,
        category: Category = .other,
        receipt: Receipt? = nil
    ) {
        self.id = id
        self.productName = productName
        self.price = price
        self.category = category
        self.receipt = receipt
    }
}

extension LineItem {
    var formattedPrice: String {
        Formatting.price(price)
    }
}
