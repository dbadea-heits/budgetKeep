import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
    case food
    case household
    case sweets
    case processedFood
    case beverages
    case personalCare
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: return "Food"
        case .household: return "Household"
        case .sweets: return "Sweets"
        case .processedFood: return "Processed Food"
        case .beverages: return "Beverages"
        case .personalCare: return "Personal Care"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .food: return "🥦"
        case .household: return "🧹"
        case .sweets: return "🍫"
        case .processedFood: return "🥫"
        case .beverages: return "🥤"
        case .personalCare: return "🧴"
        case .other: return "📦"
        }
    }

    var colorHex: String {
        switch self {
        case .food: return "4CAF50"
        case .household: return "9C27B0"
        case .sweets: return "FF9800"
        case .processedFood: return "FF5722"
        case .beverages: return "2196F3"
        case .personalCare: return "E91E63"
        case .other: return "607D8B"
        }
    }
}
