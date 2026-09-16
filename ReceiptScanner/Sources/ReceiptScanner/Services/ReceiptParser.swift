import Foundation

/// Holds the structured result of parsing raw OCR receipt text.
struct ParsedReceipt {
    var storeName: String?
    var date: Date?
    var total: Decimal?
    var paymentMethod: String?
    var lineItems: [ParsedLineItem]
    var rawText: String
}

struct ParsedLineItem {
    var productName: String
    var quantity: Decimal
    var unitPrice: Decimal?
    var price: Decimal

    init(productName: String, quantity: Decimal = 1, unitPrice: Decimal? = nil, price: Decimal) {
        self.productName = productName
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.price = price
    }
}

// MARK: - Line Classification

/// Classifies what role a line plays on the receipt.
private enum LineRole {
    /// Product name only, no price (first line of a two-line item)
    case productNameOnly(name: String)
    /// Full item on a single line: name + optional qty + price
    case completeItem(name: String, quantity: Decimal, unitPrice: Decimal?, lineTotal: Decimal)
    /// Quantity/price info only, no product name (second line of a two-line item)
    case quantityPriceLine(quantity: Decimal, unitPrice: Decimal?, lineTotal: Decimal)
    /// Discount/reduction line
    case discount(name: String, amount: Decimal)
    /// Separator, header noise, footer — skip
    case skip
    /// Definitive end of items section
    case endOfItems
}

/// Parses raw OCR text from Romanian "bon fiscal" receipts into structured data.
/// Supports multiple receipt layouts common across Romanian retailers:
///
/// **Format A** — Single-line items (Mega Image, Lidl, Penny):
/// ```
/// LAPTE ZUZU 1L              4,50
/// ```
///
/// **Format B** — Two-line, name first (Carrefour, Auchan):
/// ```
/// LAPTE ZUZU 1L
///     1 BUC x 4,50           4,50 B
/// ```
///
/// **Format C** — Two-line, qty first (Kaufland, some Profi):
/// ```
/// 2 x 5,99
/// LAPTE ZUZU 1L             11,98 B
/// ```
///
/// **Format D** — Weight-based items (produce sections):
/// ```
/// MERE GOLDEN
/// 0,520 KG x 6,99           3,63 B
/// ```
///
/// **Format E** — Multi-column with line numbers (pharmacies, some hypermarkets):
/// ```
/// 1  LAPTE ZUZU 1L    1 BUC    4,50     4,50
/// ```
enum ReceiptParser {

    // MARK: - Public API

    /// Parse raw OCR text into a ParsedReceipt.
    static func parse(_ rawText: String) -> ParsedReceipt {
        let lines = rawText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let storeName = extractStoreName(from: lines)
        let date = extractDate(from: lines)
        let paymentMethod = extractPaymentMethod(from: lines)
        let total = extractTotal(from: lines)
        let lineItems = extractLineItems(from: lines, total: total)

        return ParsedReceipt(
            storeName: storeName,
            date: date,
            total: total,
            paymentMethod: paymentMethod,
            lineItems: lineItems,
            rawText: rawText
        )
    }

    // MARK: - Constants & Patterns

    /// TVA group codes appended to prices on Romanian receipts (A=9%, B=19%, C=5%, D=0%, E=exempt).
    private static let tvaCodePattern = try! NSRegularExpression(
        pattern: "\\s+[A-E]\\s*$"
    )

    /// Matches quantity expressions: "2 x 5,99", "0,520 KG x 6,99", "2 BUC x 5,99", "2x5,99"
    private static let qtyTimesPattern = try! NSRegularExpression(
        pattern: "([\\d]+[,.]?[\\d]*)\\s*(?:BUC\\.?|KG|G|L|ML|M)?\\s*[xX*]\\s*([\\d]+[,.]?[\\d]*)",
        options: [.caseInsensitive]
    )

    /// Matches a leading line/item number: "1  LAPTE" or "01. LAPTE"
    private static let lineNumberPrefix = try! NSRegularExpression(
        pattern: "^\\d{1,3}[.\\s)]+\\s*"
    )

    /// Units of measure commonly found on Romanian receipts.
    private static let unitMarkers: Set<String> = [
        "BUC", "BUC.", "KG", "G", "L", "ML", "M", "LT", "SET", "PACH", "PAC", "PACHET"
    ]

    // MARK: - Separator Detection

    private static func isSeparatorLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty { return true }
        let separatorChars = CharacterSet(charactersIn: "-=*_·. ")
        return stripped.allSatisfy { $0.unicodeScalars.allSatisfy { separatorChars.contains($0) } }
    }

    private static func isNumericLine(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.isEmpty { return false }
        let allowed = CharacterSet(charactersIn: "0123456789.,/:; ")
        return stripped.allSatisfy { $0.unicodeScalars.allSatisfy { allowed.contains($0) } }
    }

    // MARK: - Store Name

    private static let headerNoise: Set<String> = [
        "BON FISCAL", "BON", "FISCAL", "TICKET", "RECEIPT",
        "CUI", "J", "REGISTRU", "NR", "TVA", "CASA", "AMEF",
        "ORIGINAL", "BONUL", "COPIE"
    ]

    private static let addressMarkers: Set<String> = [
        "ADRESA", "STR", "STRADA", "BD", "B-DUL", "BULEVARDUL",
        "SECTOR", "SAT", "COMUNA", "MUNICIPIUL", "JUDET", "JUDETUL",
        "ORAS", "ORASUL", "LOCALITATEA", "BL", "SC", "AP", "ET",
        "TEL", "EMAIL", "WEB", "WWW",
        "CUI", "CIF", "J/", "J ", "NR. REG", "NR REG", "NR.REG",
        "COD FISCAL", "COD UNIC"
    ]

    private static let footerMarkers: Set<String> = [
        "TOTAL", "DE PLATA", "DE PLATĂ",
        "TVA", "REST", "PLATA", "CARD", "CEC", "BANCA",
        "NUMAR", "NR CARD", "SOLD", "VIRAT", "PLĂTIT", "PLATIT"
    ]

    private static let subtotalMarkers: Set<String> = [
        "SUBTOTAL", "SUB", "SUBT", "STL"
    ]

    /// Discount/reduction markers.
    private static let discountMarkers: Set<String> = [
        "REDUCERE", "DISCOUNT", "PROMO", "PROMOTIE", "PROMOȚIE",
        "BONIFIC", "REMIZA", "REMIZĂ"
    ]

    private static func extractStoreName(from lines: [String]) -> String? {
        for line in lines {
            if isSeparatorLine(line) { continue }
            if isNumericLine(line) { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if headerNoise.contains(where: { upper.hasPrefix($0) }) { continue }
            if addressMarkers.contains(where: { upper.contains($0) }) { continue }
            if upper.hasPrefix("RO") && upper.dropFirst(2).allSatisfy({ $0.isNumber }) { continue }
            if trimmed.count < 3 { continue }

            return trimmed
        }
        return nil
    }

    // MARK: - Date

    private static let datePattern = try! NSRegularExpression(
        pattern: "\\b(\\d{2})\\.(\\d{2})\\.(\\d{4})\\b"
    )

    private static func extractDate(from lines: [String]) -> Date? {
        for line in lines {
            if let match = datePattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                let dayStr = (line as NSString).substring(with: match.range(at: 1))
                let monthStr = (line as NSString).substring(with: match.range(at: 2))
                let yearStr = (line as NSString).substring(with: match.range(at: 3))

                var components = DateComponents()
                components.day = Int(dayStr)
                components.month = Int(monthStr)
                components.year = Int(yearStr)

                let calendar = Calendar(identifier: .gregorian)
                if let date = calendar.date(from: components) {
                    return date
                }
            }
        }
        return nil
    }

    // MARK: - Payment Method

    private static func extractPaymentMethod(from lines: [String]) -> String? {
        for line in lines {
            let upper = line.uppercased()
            if upper.contains("CARD") {
                return "Card"
            }
            if upper.contains("CEC") {
                return "Cec"
            }
            if upper.contains("BANCA") && upper.contains("TRANSFER") {
                return "Transfer bancar"
            }
        }
        return nil
    }

    // MARK: - Total

    private static let totalPattern = try! NSRegularExpression(
        pattern: "TOTAL\\s*(?:LEI|RON)?\\s*([\\d]+[,\\.]?[\\d]*)",
        options: [.caseInsensitive]
    )

    private static let dePlataPattern = try! NSRegularExpression(
        pattern: "DE\\s+PLAT[AĂ]\\s*(?:LEI|RON)?\\s*([\\d]+[,\\.]?[\\d]*)",
        options: [.caseInsensitive]
    )

    private static func extractTotal(from lines: [String]) -> Decimal? {
        // First: "DE PLATĂ" / "DE PLATA"
        for line in lines {
            let upper = line.uppercased()
            let normalized = upper.replacingOccurrences(of: "Ă", with: "A")

            if let match = dePlataPattern.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)) {
                let numberStr = (normalized as NSString).substring(with: match.range(at: 1))
                if let total = parseDecimal(numberStr) {
                    return total
                }
            }
        }

        // Second: "TOTAL"
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            if !upper.contains("TOTAL") { continue }
            // Skip "SUBTOTAL" lines — only want "TOTAL"
            if upper.contains("SUBTOTAL") { continue }

            if let match = totalPattern.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)) {
                let numberStr = (upper as NSString).substring(with: match.range(at: 1))
                if let total = parseDecimal(numberStr) {
                    return total
                }
            }

            // Fallback: any decimal on a line containing TOTAL
            let tokens = trimmed.split(separator: " ")
            for token in tokens.reversed() {
                let cleaned = token
                    .trimmingCharacters(in: CharacterSet(charactersIn: "RONLei "))
                    .replacingOccurrences(of: ",", with: ".")
                if let total = Decimal(string: cleaned), total > 0 {
                    return total
                }
            }
        }

        // Third: "SUBTOTAL" as ultimate fallback
        for line in lines {
            let upper = line.uppercased()
            if upper.contains("SUBTOTAL") || upper.contains("DE PLATA") || upper.contains("DE PLATĂ") {
                let tokens = line.split(separator: " ")
                for token in tokens.reversed() {
                    let cleaned = String(token).replacingOccurrences(of: ",", with: ".")
                    if let total = Decimal(string: cleaned), total > 0 {
                        return total
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Line Items Extraction (Multi-Format)

    /// Items section start markers — used to skip header lines before items begin.
    private static let itemsStartMarkers: Set<String> = [
        "BON FISCAL", "CANTITATEA", "CANTITATE", "CANT", "DENUMIREA",
        "DENUMIRE", "NR.CRT", "PRODUS", "BUC", "ARTICOL"
    ]

    /// Column header noise inside the items section.
    private static let itemRowNoise: Set<String> = [
        "BUC", "BUC.", "CANT", "CANT.", "PRET", "VAL",
        "DENUMIRE", "UM", "NR.CRT", "CUI", "LEI", "RON",
        "CANTITATEA", "CANTITATE", "DENUMIREA", "PRETUL",
        "NR", "CRT", "ARTICOL"
    ]

    /// Strip a trailing TVA code (A-E) from a line for cleaner parsing.
    private static func stripTvaCode(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        return tvaCodePattern.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }

    /// Strip a leading line/item number from a line.
    private static func stripLineNumber(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        return lineNumberPrefix.stringByReplacingMatches(in: line, range: range, withTemplate: "")
    }

    /// Classify a single line into a LineRole.
    private static func classifyLine(_ rawLine: String) -> LineRole {
        let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
        let upper = trimmed.uppercased()

        // Separators
        if isSeparatorLine(trimmed) || trimmed.count < 2 { return .skip }

        // End of items
        if footerMarkers.contains(where: { upper.hasPrefix($0) }) { return .endOfItems }

        // Subtotals — skip but don't end
        if subtotalMarkers.contains(where: { upper.hasPrefix($0) }) { return .skip }

        // Column headers
        let allTokens = trimmed.split(separator: " ", omittingEmptySubsequences: true).map { $0.uppercased() }
        if allTokens.allSatisfy({ itemRowNoise.contains(String($0)) || $0.count <= 2 }) && allTokens.count >= 2 {
            return .skip
        }

        // Address / fiscal data that may appear in items range
        if addressMarkers.contains(where: { upper.contains($0) }) { return .skip }
        if upper.hasPrefix("RO") && upper.dropFirst(2).allSatisfy({ $0.isNumber }) { return .skip }

        // Strip TVA code for parsing (but keep original for name extraction)
        let cleaned = stripTvaCode(trimmed)
        let withoutLineNum = stripLineNumber(cleaned)

        // Check for discounts (negative amounts)
        if discountMarkers.contains(where: { upper.contains($0) }) {
            if let amount = extractTrailingPrice(from: cleaned) {
                let absAmount = amount < 0 ? amount : -amount
                let name = extractLeadingName(from: cleaned) ?? "Reducere"
                return .discount(name: name, amount: absAmount)
            }
            return .skip
        }

        // Try to extract qty × price pattern (e.g., "2 x 5,99" or "0,520 KG x 6,99 11,98")
        if let qtyMatch = parseQtyTimesExpression(from: withoutLineNum) {
            let remainingName = extractNameExcludingQtyPrice(from: withoutLineNum, qtyMatch: qtyMatch)

            if let name = remainingName, !name.isEmpty {
                // Complete item: has name + qty info + price on same line
                // e.g. "LAPTE 2 x 5,99 11,98" or "1 LAPTE ZUZU 2 BUC x 4,50  9,00"
                let lineTotal = qtyMatch.lineTotal ?? (qtyMatch.quantity * qtyMatch.unitPrice)
                return .completeItem(
                    name: name,
                    quantity: qtyMatch.quantity,
                    unitPrice: qtyMatch.unitPrice,
                    lineTotal: lineTotal
                )
            } else {
                // Qty/price only — no product name on this line
                // e.g. "2 x 5,99" or "0,520 KG x 6,99  3,63"
                let lineTotal = qtyMatch.lineTotal ?? (qtyMatch.quantity * qtyMatch.unitPrice)
                return .quantityPriceLine(
                    quantity: qtyMatch.quantity,
                    unitPrice: qtyMatch.unitPrice,
                    lineTotal: lineTotal
                )
            }
        }

        // Try single-line extraction: "PRODUCT NAME   12,50"
        if let price = extractTrailingPrice(from: withoutLineNum) {
            let name = extractLeadingName(from: withoutLineNum)

            if let productName = name, productName.count >= 2 && !isNumericLine(productName) {
                return .completeItem(name: productName, quantity: 1, unitPrice: nil, lineTotal: price)
            } else if name == nil || name!.isEmpty {
                // Price-only line (no recognizable name before the number)
                return .quantityPriceLine(quantity: 1, unitPrice: nil, lineTotal: price)
            }
        }

        // No price found → this is a product name only
        let candidateName = stripLineNumber(trimmed).trimmingCharacters(in: .whitespaces)
        if candidateName.count >= 2 && !isNumericLine(candidateName) {
            return .productNameOnly(name: candidateName)
        }

        return .skip
    }

    /// Main extraction: classifies lines, then assembles items using context.
    private static func extractLineItems(from lines: [String], total: Decimal?) -> [ParsedLineItem] {
        guard let (startIdx, endIdx) = findItemsSection(in: lines) else {
            return []
        }

        // Phase 1: Classify all lines in the items section
        var classified: [(index: Int, role: LineRole)] = []
        for i in startIdx..<endIdx {
            let role = classifyLine(lines[i])
            switch role {
            case .endOfItems:
                break
            case .skip:
                continue
            default:
                classified.append((i, role))
            }
            if case .endOfItems = role { break }
        }

        // Phase 2: Assemble items from classified lines using look-ahead/look-behind
        var items: [ParsedLineItem] = []
        var i = 0

        while i < classified.count {
            let (_, role) = classified[i]

            switch role {
            case .completeItem(let name, let qty, let unitPrice, let lineTotal):
                items.append(ParsedLineItem(
                    productName: name, quantity: qty, unitPrice: unitPrice, price: lineTotal
                ))
                i += 1

            case .productNameOnly(let name):
                // Look ahead: next line should be qty/price info (Format B / Format D)
                if i + 1 < classified.count {
                    let (_, nextRole) = classified[i + 1]
                    switch nextRole {
                    case .quantityPriceLine(let qty, let unitPrice, let lineTotal):
                        items.append(ParsedLineItem(
                            productName: name, quantity: qty, unitPrice: unitPrice, price: lineTotal
                        ))
                        i += 2
                        continue
                    case .completeItem:
                        // Next line is a complete item — this name is orphaned.
                        // Could be a multi-name line; attach as a standalone if there's context.
                        // For now, skip orphaned names (they're often header remnants).
                        i += 1
                        continue
                    default:
                        break
                    }
                }
                // No matching price line found — orphaned name, skip
                i += 1

            case .quantityPriceLine(let qty, let unitPrice, let lineTotal):
                // Look ahead: next line should be a product name (Format C — qty first, name second)
                if i + 1 < classified.count {
                    let (_, nextRole) = classified[i + 1]
                    switch nextRole {
                    case .productNameOnly(let name):
                        items.append(ParsedLineItem(
                            productName: name, quantity: qty, unitPrice: unitPrice, price: lineTotal
                        ))
                        i += 2
                        continue
                    case .completeItem(let name, _, _, let nextTotal):
                        // Format C variant: qty line, then "NAME TOTAL" on next line
                        // The next line's price is the line total; use it if it matches qty*unitPrice
                        if let up = unitPrice, abs(nextTotal - qty * up) < 0.02 {
                            items.append(ParsedLineItem(
                                productName: name, quantity: qty, unitPrice: up, price: nextTotal
                            ))
                            i += 2
                            continue
                        }
                        // Otherwise, treat them as independent items
                        items.append(ParsedLineItem(
                            productName: "Produs", quantity: qty, unitPrice: unitPrice, price: lineTotal
                        ))
                        i += 1
                        continue
                    default:
                        break
                    }
                }
                // No name follows — use placeholder
                items.append(ParsedLineItem(
                    productName: "Produs", quantity: qty, unitPrice: unitPrice, price: lineTotal
                ))
                i += 1

            case .discount(let name, let amount):
                items.append(ParsedLineItem(productName: name, quantity: 1, price: amount))
                i += 1

            case .skip, .endOfItems:
                i += 1
            }
        }

        return items
    }

    // MARK: - Items Section Boundaries

    private static func findItemsSection(in lines: [String]) -> (start: Int, end: Int)? {
        var firstProductIdx: Int? = nil
        var endMarkerIdx: Int? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()

            if trimmed.isEmpty { continue }
            if isSeparatorLine(trimmed) { continue }

            // Skip subtotal lines
            if subtotalMarkers.contains(where: { upper.hasPrefix($0) }) { continue }

            // Check for definitive footer/end markers
            if footerMarkers.contains(where: { upper.hasPrefix($0) }) {
                endMarkerIdx = i
                break
            }

            // Skip obvious header lines before first product
            if firstProductIdx == nil {
                if itemsStartMarkers.contains(where: { upper.contains($0) }) { continue }
                if headerNoise.contains(where: { upper.hasPrefix($0) }) { continue }
                if addressMarkers.contains(where: { upper.contains($0) }) { continue }
                if isNumericLine(trimmed) { continue }
                // Skip pure letter lines (city names, county, etc.)
                if trimmed.count <= 25 && trimmed.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "." }) {
                    continue
                }
            }

            // Does this line look like it has product/price content?
            if hasPriceToken(trimmed) || hasQtyTimesExpression(trimmed) {
                if firstProductIdx == nil {
                    // First price line. Look back for product names.
                    firstProductIdx = i
                    let maxLookback = min(i, 3)
                    for offset in 1...maxLookback {
                        let candidate = lines[i - offset].trimmingCharacters(in: .whitespaces)
                        if candidate.isEmpty || isSeparatorLine(candidate) { break }
                        let candUpper = candidate.uppercased()
                        if footerMarkers.contains(where: { candUpper.hasPrefix($0) }) ||
                           addressMarkers.contains(where: { candUpper.contains($0) }) ||
                           headerNoise.contains(where: { candUpper.hasPrefix($0) }) ||
                           isNumericLine(candidate) { break }
                        if candidate.count < 2 { break }
                        firstProductIdx = i - offset
                    }
                }
            } else if firstProductIdx == nil {
                // Non-price lines before items — continue scanning
                if addressMarkers.contains(where: { upper.contains($0) }) { continue }
                if upper.hasPrefix("RO") && upper.dropFirst(2).allSatisfy({ $0.isNumber }) { continue }
                if upper.hasPrefix("J") && upper.dropFirst().prefix(1).allSatisfy({ $0.isNumber }) { continue }
            }
        }

        guard let start = firstProductIdx else { return nil }
        return (start, endMarkerIdx ?? lines.count)
    }

    // MARK: - Price & Quantity Extraction

    /// Result of parsing a "qty x unitPrice [lineTotal]" expression.
    private struct QtyPriceMatch {
        var quantity: Decimal
        var unitPrice: Decimal
        var lineTotal: Decimal?
        /// Range in the original string that the qty×price expression occupies.
        var matchRange: Range<String.Index>
    }

    /// Check if a line contains a qty × price expression.
    private static func hasQtyTimesExpression(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return qtyTimesPattern.firstMatch(in: line, range: range) != nil
    }

    /// Parse a "qty x unitPrice [lineTotal]" expression from a line.
    private static func parseQtyTimesExpression(from line: String) -> QtyPriceMatch? {
        let nsRange = NSRange(line.startIndex..., in: line)
        guard let match = qtyTimesPattern.firstMatch(in: line, range: nsRange) else {
            return nil
        }

        guard let qtyRange = Range(match.range(at: 1), in: line),
              let upRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        guard let quantity = parseDecimal(String(line[qtyRange])),
              let unitPrice = parseDecimal(String(line[upRange])) else {
            return nil
        }

        guard let fullRange = Range(match.range, in: line) else {
            return nil
        }

        // Look for a line total after the qty×price expression
        let afterMatch = String(line[fullRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        var lineTotal: Decimal? = nil

        if !afterMatch.isEmpty {
            // Strip TVA code and try to parse remaining as price
            let stripped = stripTvaCode(afterMatch).trimmingCharacters(in: .whitespaces)
            let tokens = stripped.split(separator: " ", omittingEmptySubsequences: true)
            for token in tokens {
                let tokenStr = String(token).uppercased()
                if tokenStr == "RON" || tokenStr == "LEI" { continue }
                if unitMarkers.contains(tokenStr) { continue }
                if let val = parseDecimal(String(token)) {
                    lineTotal = val
                    break
                }
            }
        }

        return QtyPriceMatch(
            quantity: quantity,
            unitPrice: unitPrice,
            lineTotal: lineTotal,
            matchRange: fullRange
        )
    }

    /// Extract the product name from a line that contains a qty×price match.
    private static func extractNameExcludingQtyPrice(from line: String, qtyMatch: QtyPriceMatch) -> String? {
        // Everything before the qty×price match is the product name
        let beforeMatch = String(line[line.startIndex..<qtyMatch.matchRange.lowerBound])
            .trimmingCharacters(in: .whitespaces)

        // Strip unit markers and trailing noise
        var name = beforeMatch
        let tokens = name.split(separator: " ", omittingEmptySubsequences: true)

        // Remove trailing unit markers (BUC, KG, etc.) and pure numbers from the name
        var nameTokens: [String] = []
        for token in tokens {
            let upper = token.uppercased()
            if unitMarkers.contains(String(upper)) { continue }
            // Skip standalone numbers at end (could be line numbers or qty)
            if nameTokens.isEmpty && parseDecimal(String(token)) != nil { continue }
            nameTokens.append(String(token))
        }

        name = nameTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Extract the trailing price from a line (rightmost decimal number).
    private static func extractTrailingPrice(from line: String) -> Decimal? {
        let cleaned = stripTvaCode(line).trimmingCharacters(in: .whitespaces)
        let tokens = cleaned.split(separator: " ", omittingEmptySubsequences: true)

        for token in tokens.reversed() {
            let upper = token.uppercased()
            if upper == "RON" || upper == "LEI" { continue }
            if unitMarkers.contains(String(upper)) { continue }
            // Must contain a decimal separator to be a real price
            if !token.contains(".") && !token.contains(",") { continue }
            if let val = parseDecimal(String(token)) {
                return val
            }
        }
        return nil
    }

    /// Extract the product name (everything before the first price-like token).
    private static func extractLeadingName(from line: String) -> String? {
        let cleaned = stripTvaCode(line).trimmingCharacters(in: .whitespaces)
        let tokens = cleaned.split(separator: " ", omittingEmptySubsequences: true)

        var nameTokens: [String] = []
        for token in tokens {
            let str = String(token)
            // Stop at first token that looks like a price (has decimal separator and parses)
            if (str.contains(".") || str.contains(",")) && parseDecimal(str) != nil {
                break
            }
            // Also stop at "x" or "*" (qty separator)
            if str.uppercased() == "X" || str == "*" {
                // Check if previous token was a number (quantity) — remove it from name
                if let last = nameTokens.last, parseDecimal(last) != nil {
                    nameTokens.removeLast()
                }
                break
            }
            nameTokens.append(str)
        }

        let name = nameTokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Quick check: does this line contain at least one token that looks like a real price?
    private static func hasPriceToken(_ line: String) -> Bool {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 2 else { return false }
        for token in tokens.reversed() {
            let upper = token.uppercased()
            if upper == "RON" || upper == "LEI" || upper == "A" || upper == "B" ||
               upper == "C" || upper == "D" || upper == "E" || upper == "BX" { continue }
            if !token.contains(".") && !token.contains(",") { continue }
            if parseDecimal(String(token)) != nil { return true }
        }
        return false
    }

    // MARK: - Decimal Parsing

    /// Parse a decimal string, handling both `,` and `.` as decimal separators.
    /// For Romanian receipts, `,` is the decimal separator (e.g., "12,50").
    static func parseDecimal(_ string: String) -> Decimal? {
        let cleaned = string.trimmingCharacters(in: CharacterSet(charactersIn: "RONron Lei BXbx "))

        // Handle "x12,50" or "2x12,50" quantity+price formats
        if let xRange = cleaned.range(of: "x", options: .caseInsensitive) {
            let pricePart = String(cleaned[xRange.upperBound...])
            return parseDecimal(pricePart)
        }

        // Negative values (discounts): "-1,50" or "- 1,50"
        var isNegative = false
        var numberStr = cleaned
        if numberStr.hasPrefix("-") {
            isNegative = true
            numberStr = String(numberStr.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // European format with both separators: "1.234,56"
        if numberStr.contains(",") && numberStr.contains(".") {
            let european = numberStr
                .replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            if let val = Decimal(string: european, locale: Locale(identifier: "en_US")) {
                return isNegative ? -val : val
            }
            return nil
        }

        // Comma as decimal separator: "12,50"
        if numberStr.contains(",") {
            let normalized = numberStr.replacingOccurrences(of: ",", with: ".")
            if let val = Decimal(string: normalized, locale: Locale(identifier: "en_US")) {
                return isNegative ? -val : val
            }
            return nil
        }

        // Plain decimal: "12.50"
        if let val = Decimal(string: numberStr, locale: Locale(identifier: "en_US")) {
            return isNegative ? -val : val
        }
        return nil
    }
}
