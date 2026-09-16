import XCTest
@testable import ReceiptScanner

final class ReceiptParserTests: XCTestCase {

    // MARK: - Format A: Single-line items (Mega Image, Lidl, Penny)

    func testParseRomanianReceipt() {
        let text = """
        MEGA IMAGE SRL
        CUI: RO12345678
        BON FISCAL
        09.03.2026  14:32
        ----------------------------
        Lapte 1L              4.50
        Paine graham           3.20
        Ciocolata Milka      12.90
        Detergent lichid     18.50
        ----------------------------
        TOTAL             39.10 RON
        Numar bilete: 4
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.storeName?.lowercased(), "mega image srl")
        XCTAssertEqual(parsed.lineItems.count, 4)
        XCTAssertEqual(parsed.total, 39.10)

        XCTAssertTrue(parsed.lineItems[0].productName.lowercased().contains("lapte"))
        XCTAssertEqual(parsed.lineItems[0].price, 4.50)

        XCTAssertTrue(parsed.lineItems[1].productName.lowercased().contains("paine"))
        XCTAssertEqual(parsed.lineItems[1].price, 3.20)
    }

    func testParseReceiptWithCommaDecimal() {
        let text = """
        CARREFOUR
        15.06.2026
        Apa plata 1,5L      2,50
        Paine alba            3,00
        --------------------
        TOTAL               5,50
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 2)
        XCTAssertEqual(parsed.lineItems[0].price, 2.50)
        XCTAssertEqual(parsed.lineItems[1].price, 3.00)
        XCTAssertEqual(parsed.total, 5.50)
    }

    func testParseReceiptWithRONAfterPrice() {
        let text = """
        LIDL
        22.04.2026
        Lapte 1,5%        4.50 RON
        Paine neagra      3.20 RON
        Branza             8.90 RON
        TOTAL             16.60 RON
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)
        XCTAssertEqual(parsed.lineItems[2].productName, "Branza")
    }

    func testParseSimpleReceipt() {
        let text = """
        PENNY MARKET
        05.01.2027
        Mere              3.99
        Banane            4.50
        Lapte             5.00
        TOTAL            13.49
        """

        let parsed = ReceiptParser.parse(text)
        XCTAssertNotNil(parsed.storeName)
        XCTAssertTrue(parsed.storeName!.lowercased().contains("penny"))
        XCTAssertEqual(parsed.lineItems.count, 3)
        XCTAssertEqual(parsed.total, 13.49)
    }

    // MARK: - Format A with TVA codes (single letter at end)

    func testParseSingleLineWithTvaCodes() {
        let text = """
        PROFI ROM FOOD SRL
        12.05.2026
        LAPTE ZUZU 1L         4,50 B
        PAINE ALBA            3,20 A
        CIOCOLATA HEIDI       7,90 B
        TOTAL                15,60
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)
        XCTAssertTrue(parsed.lineItems[0].productName.contains("LAPTE"))
        XCTAssertEqual(parsed.lineItems[0].price, 4.50)
        XCTAssertEqual(parsed.lineItems[1].price, 3.20)
        XCTAssertEqual(parsed.lineItems[2].price, 7.90)
    }

    // MARK: - Format B: Two-line, name first (Carrefour, Auchan)

    func testParseTwoLineNameFirst() {
        let text = """
        CARREFOUR ROMANIA SA
        CUI: RO234567890
        Str. Barbu Vacarescu 120
        01.07.2026  18:45
        ----------------------------
        LAPTE ZUZU 1L
        1 x 4,50              4,50 B
        PAINE INTEGRALA
        2 x 3,20              6,40 B
        BRANZA TELEMEA
        1 x 12,90            12,90 B
        ----------------------------
        TOTAL                23,80 RON
        CARD
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)

        XCTAssertEqual(parsed.lineItems[0].productName, "LAPTE ZUZU 1L")
        XCTAssertEqual(parsed.lineItems[0].quantity, 1)
        XCTAssertEqual(parsed.lineItems[0].price, 4.50)

        XCTAssertEqual(parsed.lineItems[1].productName, "PAINE INTEGRALA")
        XCTAssertEqual(parsed.lineItems[1].quantity, 2)
        XCTAssertEqual(parsed.lineItems[1].price, 6.40)

        XCTAssertEqual(parsed.lineItems[2].productName, "BRANZA TELEMEA")
        XCTAssertEqual(parsed.lineItems[2].quantity, 1)
        XCTAssertEqual(parsed.lineItems[2].price, 12.90)
    }

    func testParseTwoLineNameFirstWithBuc() {
        let text = """
        AUCHAN ROMANIA
        18.03.2026
        ---
        DETERGENT ARIEL 2L
        1 BUC x 32,90        32,90 B
        APA PLATA DORNA 2L
        3 BUC x 4,50         13,50 B
        ---
        TOTAL                46,40
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 2)
        XCTAssertEqual(parsed.lineItems[0].productName, "DETERGENT ARIEL 2L")
        XCTAssertEqual(parsed.lineItems[0].quantity, 1)
        XCTAssertEqual(parsed.lineItems[0].price, 32.90)

        XCTAssertEqual(parsed.lineItems[1].productName, "APA PLATA DORNA 2L")
        XCTAssertEqual(parsed.lineItems[1].quantity, 3)
        XCTAssertEqual(parsed.lineItems[1].price, 13.50)
    }

    // MARK: - Format C: Two-line, qty first (Kaufland, some Profi)

    func testParseTwoLineQtyFirst() {
        let text = """
        KAUFLAND ROMANIA
        CUI: RO345678901
        05.08.2026  09:12
        ============================
        2 x 5,99
        LAPTE ZUZU 1L
        1 x 3,20
        PAINE ALBA 500G
        3 x 7,90
        IAURT DANONE 125G
        ============================
        TOTAL                32,88
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)

        XCTAssertEqual(parsed.lineItems[0].productName, "LAPTE ZUZU 1L")
        XCTAssertEqual(parsed.lineItems[0].quantity, 2)
        XCTAssertEqual(parsed.lineItems[0].unitPrice, 5.99)
        XCTAssertEqual(parsed.lineItems[0].price, 11.98)

        XCTAssertEqual(parsed.lineItems[1].productName, "PAINE ALBA 500G")
        XCTAssertEqual(parsed.lineItems[1].quantity, 1)
        XCTAssertEqual(parsed.lineItems[1].price, 3.20)

        XCTAssertEqual(parsed.lineItems[2].productName, "IAURT DANONE 125G")
        XCTAssertEqual(parsed.lineItems[2].quantity, 3)
        XCTAssertEqual(parsed.lineItems[2].unitPrice, 7.90)
        XCTAssertEqual(parsed.lineItems[2].price, 23.70)
    }

    func testParseTwoLineQtyFirstWithLineTotal() {
        let text = """
        KAUFLAND
        10.10.2026
        ---
        2 x 5,99             11,98
        LAPTE ZUZU 1L
        1 x 14,50            14,50
        ULEI FLOAREA SOARELUI
        ---
        TOTAL                26,48
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 2)
        XCTAssertEqual(parsed.lineItems[0].productName, "LAPTE ZUZU 1L")
        XCTAssertEqual(parsed.lineItems[0].price, 11.98)
        XCTAssertEqual(parsed.lineItems[1].productName, "ULEI FLOAREA SOARELUI")
        XCTAssertEqual(parsed.lineItems[1].price, 14.50)
    }

    // MARK: - Format D: Weight-based items (produce)

    func testParseWeightBasedItems() {
        let text = """
        MEGA IMAGE
        20.09.2026
        ---
        MERE GOLDEN
        0,520 KG x 6,99      3,63 B
        ROSII ROMANESTI
        1,200 KG x 8,50     10,20 B
        LAPTE UHT            5,90 B
        ---
        TOTAL                19,73
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)

        XCTAssertEqual(parsed.lineItems[0].productName, "MERE GOLDEN")
        XCTAssertEqual(parsed.lineItems[0].quantity, 0.52)
        XCTAssertEqual(parsed.lineItems[0].unitPrice, 6.99)
        XCTAssertEqual(parsed.lineItems[0].price, 3.63)

        XCTAssertEqual(parsed.lineItems[1].productName, "ROSII ROMANESTI")
        XCTAssertEqual(parsed.lineItems[1].quantity, 1.2)
        XCTAssertEqual(parsed.lineItems[1].unitPrice, 8.50)
        XCTAssertEqual(parsed.lineItems[1].price, 10.20)

        // Single-line item mixed in
        XCTAssertEqual(parsed.lineItems[2].productName, "LAPTE UHT")
        XCTAssertEqual(parsed.lineItems[2].price, 5.90)
    }

    // MARK: - Format E: Mixed formats in one receipt

    func testParseMixedFormats() {
        let text = """
        LIDL ROMANIA
        03.11.2026
        ---
        BANANE               5,49 B
        CIOCOLATA FIN
        2 x 4,99             9,98 B
        HARTIE IGIENICA     12,90 B
        ROSII
        0,850 KG x 9,99      8,49 B
        ---
        TOTAL                36,86
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 4)

        // Single-line
        XCTAssertEqual(parsed.lineItems[0].productName, "BANANE")
        XCTAssertEqual(parsed.lineItems[0].price, 5.49)

        // Two-line name-first with qty
        XCTAssertEqual(parsed.lineItems[1].productName, "CIOCOLATA FIN")
        XCTAssertEqual(parsed.lineItems[1].quantity, 2)
        XCTAssertEqual(parsed.lineItems[1].price, 9.98)

        // Single-line
        XCTAssertEqual(parsed.lineItems[2].productName, "HARTIE IGIENICA")
        XCTAssertEqual(parsed.lineItems[2].price, 12.90)

        // Weight-based
        XCTAssertEqual(parsed.lineItems[3].productName, "ROSII")
        XCTAssertEqual(parsed.lineItems[3].quantity, 0.85)
        XCTAssertEqual(parsed.lineItems[3].price, 8.49)
    }

    // MARK: - Discount/Reduction Lines

    func testParseReceiptWithDiscounts() {
        let text = """
        MEGA IMAGE
        14.04.2026
        ---
        IAURT ACTIVIA        6,50 B
        REDUCERE            -1,00 B
        PAINE TOAST          4,90 A
        ---
        TOTAL               10,40
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)
        XCTAssertEqual(parsed.lineItems[0].productName, "IAURT ACTIVIA")
        XCTAssertEqual(parsed.lineItems[0].price, 6.50)
        XCTAssertTrue(parsed.lineItems[1].productName.contains("REDUCERE"))
        XCTAssertEqual(parsed.lineItems[1].price, -1.00)
        XCTAssertEqual(parsed.lineItems[2].productName, "PAINE TOAST")
        XCTAssertEqual(parsed.lineItems[2].price, 4.90)
    }

    // MARK: - European number format (thousands separator)

    func testParseEuropeanNumberFormat() {
        let text = """
        DEDEMAN
        28.02.2026
        MASINA SPALAT       1.299,00 B
        FRIGIDER            2.450,00 B
        TOTAL              3.749,00
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 2)
        XCTAssertEqual(parsed.lineItems[0].price, 1299.00)
        XCTAssertEqual(parsed.lineItems[1].price, 2450.00)
        XCTAssertEqual(parsed.total, 3749.00)
    }

    // MARK: - Edge Cases

    func testEmptyText() {
        let parsed = ReceiptParser.parse("")
        XCTAssertNil(parsed.storeName)
        XCTAssertNil(parsed.date)
        XCTAssertNil(parsed.total)
        XCTAssertTrue(parsed.lineItems.isEmpty)
    }

    func testDateExtraction() {
        let text = """
        PROFI
        24.12.2026  10:15
        Produs       10.00
        TOTAL       10.00
        """

        let parsed = ReceiptParser.parse(text)
        XCTAssertNotNil(parsed.date)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.day, .month, .year], from: parsed.date!)
        XCTAssertEqual(components.day, 24)
        XCTAssertEqual(components.month, 12)
        XCTAssertEqual(components.year, 2026)
    }

    func testPaymentMethodCard() {
        let text = """
        PROFI
        01.01.2027
        Produs       10,00
        TOTAL       10,00
        CARD
        """

        let parsed = ReceiptParser.parse(text)
        XCTAssertEqual(parsed.paymentMethod, "Card")
    }

    // MARK: - Real-world Romanian receipt patterns

    func testProfiStyleReceipt() {
        let text = """
        PROFI ROM FOOD SRL
        CUI RO18127350
        Str. Republicii 45
        ORADEA
        01.06.2026 12:34:56
        =============================
        LAPTE ZUZU 3.5%1L    7,49 B
        PAINE ALBA 500G      2,99 A
        OUA MARIME L 10B    11,49 B
        HARTIE IGIEN 3STR    8,99 B
        BERE URSUS 0.5L      4,99 C
        =============================
        TOTAL               35,95 LEI
        CARD                35,95
        NR CARD ****1234
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.storeName?.uppercased(), "PROFI ROM FOOD SRL")
        XCTAssertEqual(parsed.lineItems.count, 5)
        XCTAssertEqual(parsed.total, 35.95)
        XCTAssertEqual(parsed.paymentMethod, "Card")

        XCTAssertTrue(parsed.lineItems[0].productName.contains("LAPTE"))
        XCTAssertEqual(parsed.lineItems[0].price, 7.49)
        XCTAssertEqual(parsed.lineItems[4].price, 4.99)
    }

    func testKauflandTwoLineWithTvaCode() {
        let text = """
        KAUFLAND ROMANIA SCS
        CUI RO123456
        15.09.2026
        ---
        2 x 4,99              9,98 B
        IAURT MULLER 125G
        1 x 12,50            12,50 B
        CASCAVAL HOCHLAND
        0,750 KG x 24,90    18,68 B
        SUNCA PRAGA
        ---
        TOTAL                41,16
        """

        let parsed = ReceiptParser.parse(text)

        XCTAssertEqual(parsed.lineItems.count, 3)

        XCTAssertEqual(parsed.lineItems[0].productName, "IAURT MULLER 125G")
        XCTAssertEqual(parsed.lineItems[0].quantity, 2)
        XCTAssertEqual(parsed.lineItems[0].price, 9.98)

        XCTAssertEqual(parsed.lineItems[1].productName, "CASCAVAL HOCHLAND")
        XCTAssertEqual(parsed.lineItems[1].quantity, 1)
        XCTAssertEqual(parsed.lineItems[1].price, 12.50)

        XCTAssertEqual(parsed.lineItems[2].productName, "SUNCA PRAGA")
        XCTAssertEqual(parsed.lineItems[2].quantity, 0.75)
        XCTAssertEqual(parsed.lineItems[2].unitPrice, 24.90)
        XCTAssertEqual(parsed.lineItems[2].price, 18.68)
    }
}

// MARK: - Categorizer Tests

final class CategorizerTests: XCTestCase {

    func testSweetsCategory() {
        XCTAssertEqual(Categorizer.categorize("Ciocolata Milka"), .sweets)
        XCTAssertEqual(Categorizer.categorize("Biscuiti Oreo"), .sweets)
        XCTAssertEqual(Categorizer.categorize("Napolitane Crem"), .sweets)
        XCTAssertEqual(Categorizer.categorize("Gume de mestecat"), .sweets)
    }

    func testBeveragesCategory() {
        XCTAssertEqual(Categorizer.categorize("Apa minerala 1.5L"), .beverages)
        XCTAssertEqual(Categorizer.categorize("Coca Cola 0.5L"), .beverages)
        XCTAssertEqual(Categorizer.categorize("Cafea macinata"), .beverages)
        XCTAssertEqual(Categorizer.categorize("Bere Ciucas"), .beverages)
    }

    func testProcessedFoodCategory() {
        XCTAssertEqual(Categorizer.categorize("Sunca Praga"), .processedFood)
        XCTAssertEqual(Categorizer.categorize("Parizer Pui"), .processedFood)
        XCTAssertEqual(Categorizer.categorize("Pateu de casa"), .processedFood)
    }

    func testHouseholdCategory() {
        XCTAssertEqual(Categorizer.categorize("Detergent lichid"), .household)
        XCTAssertEqual(Categorizer.categorize("Hartie igienica"), .household)
        XCTAssertEqual(Categorizer.categorize("Servetele umede"), .household)
    }

    func testPersonalCareCategory() {
        XCTAssertEqual(Categorizer.categorize("Sampon"), .personalCare)
        XCTAssertEqual(Categorizer.categorize("Pasta de dinti"), .personalCare)
        XCTAssertEqual(Categorizer.categorize("Deodorant spray"), .personalCare)
    }

    func testFoodCategory() {
        XCTAssertEqual(Categorizer.categorize("Paine graham"), .food)
        XCTAssertEqual(Categorizer.categorize("Lapte 1.5%"), .food)
        XCTAssertEqual(Categorizer.categorize("Cartofi albi"), .food)
        XCTAssertEqual(Categorizer.categorize("Oua de gaina"), .food)
    }

    func testUnknownCategory() {
        XCTAssertEqual(Categorizer.categorize("Bec LED 12W"), .household)
        XCTAssertEqual(Categorizer.categorize("Bricheta"), .household)
    }
}
