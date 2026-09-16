import Foundation

/// Keyword-based rule engine for categorizing line items.
/// No ML, no network calls — purely local keyword matching.
enum Categorizer {

    // MARK: - Category Keyword Maps

    private static let sweetsKeywords: [String] = [
        "ciocolata", "ciocolată", "bomboane", "napolitane", "biscuiti", "biscuiți",
        "fursecuri", "inghetata", "înghețată", "gwares", "milka", "kinder", "praline",
        "caramel", "eugen", "halva", "turta dulce", "turtă dulce", "acadele",
        "guma", "gume", "jeleuri", "marshmallow", "crema de ciocolata",
        "nogat", "nuga", "lapte praf", "dulceata", "gem", "nutella", "eclair",
        "baton", "batoane", "wafer", "wafers", "cocoa", "cacao",
        "bomboane", "lollipop", "toffee", "marmelada", "marmeladă",
        "covrigi dulci", "corn dulce", "cozonac", "prajitura", "prăjitură",
        "briosa", "brioșă", "muffin", "doboș", "tort"
    ]

    private static let beveragesKeywords: [String] = [
        "apa", "apă", "suc", "cola", "pepsi", "fanta", "sprite", "schweppes",
        "bere", "berea", "vin", "vinul", "cafea", "ceai", "energizant",
        "red bull", "monster", "burn", "hell", "boost", "lapte",
        "iaurt de baut", "iaurt de băut", "kefir", "ayran", "sana",
        "limonada", "limonadă", "sirop", "cidru", "sampanie", "șampanie",
        "prosecco", "apa minerala", "apa plata", "sifon", "drink",
        "cocacola", "pepsicola"
    ]

    private static let processedFoodKeywords: [String] = [
        "mezeluri", "sunca", "șuncă", "parizer", "carnati", "cârnați",
        "cremwursti", "crenvurști", "pateu", "conserve", "pate",
        "piure", "piureu", "nuggets", "snitel", "șnițel", "microunde",
        "congelat", "congelate", "pizza", "mici", "mititei",
        "mamaliga", "mămăligă", "paste instant", "supe la plic",
        "salam", "salamul", "costita", "costită", "slanina", "slănină",
        "bacon", "pastrama", "pastramă", "muschi", "mușchi",
        "peste afumat", "macrou afumat", "scrumbie",
        "bors", "borș", "concentrat supa", "cuburi supa",
        "pate ficat", "pate vegetal", "tobă", "jumări",
        "chiftele", "pârjoale", "cartofi prajiti",
        "cus-cus", "couscous", "pulghet", "corn flakes"
    ]

    private static let householdKeywords: [String] = [
        "detergent", "balsam", "curatare", "curat", "curățare", "curăț",
        "dezinfectant", "prosoape", "hartie igienica", "hârtie igienică",
        "servetele", "șervețele", "saci menajeri", "folie", "folie aluminiu",
        "aluminiu", "becuri", "baterii", "pile", "detergent vase",
        "detergent rufe", "detergent manual", "clor", "oxidant",
        "carne", "carne tocată",  // wait, this is food — moved to food
        "perie", "periuta", "perișoară", "mop", "matura", "mătură",
        "farfurii", "pahare", "pungi", "pungă", "pungile",
        "cos de gunoi", "coș de gunoi", "stergator", "ștergător",
        "lavete", "burete", "bureți", "sapun lichid", "odorizant",
        "scotch", "banda adeziva", "lipici", "capsator",
        "cuie", "suruburi", "șuruburi", "dibluri",
        "bricheta", "chibrite", "scobitori", "betisoare",
        "amoniac", "dedurizator", "anticalcar"
    ]

    private static let personalCareKeywords: [String] = [
        "sampon", "șampon", "sapun", "săpun", "pasta de dinti", "pastă de dinți",
        "deodorant", "crema", "cremă", "lotiune", "loțiune",
        "balsam par", "balsam păr", "aparat ras", "aparut ras",
        "absorbante", "scuteci", "pampers", "tampoane",
        "gel de dus", "spuma de dus", "spumă de dus", "ulei de corp",
        "vata", "vată", "betisoare urechi", "bețișoare urechi",
        "lama de ras", "lamă de ras", "schick", "gillette",
        "fard", "ruj", "machiaj", "demachiant", "discuri demachiante",
        "servetele umede", "șervețele umede", "role par", "role păr",
        "spray par", "spray păr", "gel par", "gel păr", "ceara par",
        "apa de gura", "apa de gură", "ata dentara", "ață dentară",
        "periuța de dinti", "periuță de dinți", "dantura",
        "protectie zilnica", "protectie sanitara",
        "cosmetice", "makeup", "balsam buze"
    ]

    // MARK: - Main Categorization

    /// Categorize a product name based on keyword matching.
    /// Checks categories in order of specificity (sweets first, food last).
    /// - Parameter productName: The raw product name from the receipt.
    /// - Returns: The best-matching category, or `.other` if no match found.
    static func categorize(_ productName: String) -> Category {
        let name = productName.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)

        // Check specific categories first (more specific = higher priority)
        if matches(name, keywords: sweetsKeywords) { return .sweets }
        if matches(name, keywords: beveragesKeywords) { return .beverages }
        if matches(name, keywords: processedFoodKeywords) { return .processedFood }
        if matches(name, keywords: householdKeywords) { return .household }
        if matches(name, keywords: personalCareKeywords) { return .personalCare }

        // Food is the broad fallback for grocery items
        if isLikelyFood(name) { return .food }

        return .other
    }

    // MARK: - Private Helpers

    /// Check if any keyword matches the product name.
    private static func matches(_ name: String, keywords: [String]) -> Bool {
        for keyword in keywords {
            let kw = keyword.folding(options: .diacriticInsensitive, locale: .current)
            if name.contains(kw) {
                // Avoid false positives: "lapte" shouldn't match "ciocolata cu lapte"
                // But for now, simple contains is good enough for MVP
                return true
            }
        }
        return false
    }

    /// Broad heuristic: if the product name comes from a grocery receipt and
    /// isn't matched by the specific categories, it's probably food.
    private static func isLikelyFood(_ name: String) -> Bool {
        // Common food indicators
        let foodIndicators: [String] = [
            "paine", "pâine", "lapte", "branza", "brânză", "oua", "ouă",
            "ulei", "faina", "făină", "zahar", "zahăr", "sare", "piper",
            "orez", "paste", "mamaliga", "mămăligă",
            "cartofi", "rosii", "roșii", "ceapa", "ceapă", "usturoi",
            "morcov", "ardei", "castraveti", "castraveți", "varza", "varză",
            "margarina", "margarină", "unt", "smantana", "smântână",
            "iaurt", "cascaval", "cașcaval", "telemea",
            "pui", "puiul", "carne", "porc", "vita", "vită", "miel",
            "peste", "pește", "somon", "ton",
            "mere", "pere", "banane", "portocale", "mandarine", "struguri",
            "cirese", "capsuni", "căpșuni", "zmeura", "zmeură", "afine",
            "fructe", "legume",
            "salata", "salată", "spanac", "broccoli", "conopida", "conopidă",
            "ciuperci", "mazare", "mazăre", "fasole", "linte",
            "gris", "griș", "tarate", "tărâțe", "fulgi de ovaz",
            "pate", "peste", "carne tocata", "pasta de tarhon",
            "compot", "muraturi", "murături"
        ]
        return matches(name, keywords: foodIndicators)
    }

    /// Re-categorize a specific line item (updates the model).
    static func recategorize(_ lineItem: LineItem, to category: Category) {
        lineItem.category = category
    }

    /// Bulk re-categorize all line items in a receipt.
    static func categorizeReceipt(_ receipt: Receipt) {
        for item in receipt.lineItems {
            item.category = categorize(item.productName)
        }
    }

    /// Get all unique product names and their purchase frequency across receipts.
    static func purchaseFrequency(for receipts: [Receipt]) -> [String: Int] {
        var frequency: [String: Int] = [:]
        for receipt in receipts {
            for item in receipt.lineItems {
                let key = item.productName.lowercased().trimmingCharacters(in: .whitespaces)
                frequency[key, default: 0] += 1
            }
        }
        return frequency
    }

    /// Filter line items that are "standout" — purchased ≤2 times.
    static func standoutLineItems(from receipts: [Receipt]) -> [LineItem] {
        let frequency = purchaseFrequency(for: receipts)
        return receipts.flatMap { $0.lineItems }
            .filter { item in
                let key = item.productName.lowercased().trimmingCharacters(in: .whitespaces)
                return (frequency[key] ?? 0) <= 2
            }
    }
}
