import SwiftUI
import SwiftData

/// Settings view: data management, export, about.
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    @State private var showDeleteAllConfirmation = false
    @State private var showExportSheet = false
    @State private var exportData: String?

    private var totalItemCount: Int {
        receipts.reduce(0) { $0 + $1.lineItems.count }
    }

    private var grandTotal: Decimal {
        receipts.reduce(Decimal.zero) { $0 + $1.total }
    }

    var body: some View {
        NavigationStack {
            List {
                // Storage info
                Section("Stocare") {
                    HStack {
                        Label("Bonuri", systemImage: "receipt")
                        Spacer()
                        Text("\(receipts.count)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Produse", systemImage: "shippingbox")
                        Spacer()
                        Text("\(totalItemCount)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Total cheltuit", systemImage: "creditcard.and.123")
                        Spacer()
                        Text(Formatting.price(grandTotal))
                            .foregroundColor(.secondary)
                    }
                }

                // Category rules (read-only reference)
                Section {
                    ForEach(Category.allCases, id: \.self) { cat in
                        HStack {
                            Text(cat.icon)
                            Text(cat.displayName)
                            Spacer()
                            Text("\(categoryCount(cat))")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    Text("Categorizarea se face automat pe baza numelui produsului. Poți schimba categoria oricărui produs din ecranul de detalii.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Categorii")
                }

                // Export
                Section("Export") {
                    Button {
                        exportJSON()
                    } label: {
                        Label("Exportă date ca JSON", systemImage: "square.and.arrow.up")
                    }
                }

                // Danger zone
                Section {
                    Button(role: .destructive) {
                        showDeleteAllConfirmation = true
                    } label: {
                        Label("Șterge toate datele", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                } header: {
                    Text("Pericol")
                } footer: {
                    Text("Această acțiune șterge toate bonurile și imaginile. Nu poate fi anulată.")
                }

                // About
                Section("Despre") {
                    HStack {
                        Text("Versiune")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Dezvoltat pentru")
                        Spacer()
                        Text("🇷🇴 România")
                            .foregroundColor(.secondary)
                    }
                    Text("BonScanner folosește Apple Vision pentru OCR și SwiftData pentru stocare locală. Toate datele rămân pe dispozitivul tău.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Setări")
            .alert("Șterge toate datele?", isPresented: $showDeleteAllConfirmation) {
                Button("Șterge tot", role: .destructive) { deleteAllData() }
                Button("Anulează", role: .cancel) {}
            } message: {
                Text("Toate bonurile, produsele și imaginile vor fi șterse definitiv.")
            }
            .sheet(isPresented: $showExportSheet) {
                if let data = exportData {
                    ExportView(data: data)
                }
            }
        }
    }

    private func deleteAllData() {
        // Delete all images
        for receipt in receipts {
            if let path = receipt.imagePath {
                OCRService.deleteImage(at: path)
            }
            modelContext.delete(receipt)
        }
        try? modelContext.save()
    }

    private func categoryCount(_ category: Category) -> Int {
        receipts.reduce(0) { total, receipt in
            total + receipt.lineItems.filter { $0.category == category }.count
        }
    }

    private func exportJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let exportReceipts = receipts.map { receipt -> ExportReceipt in
            ExportReceipt(
                id: receipt.id.uuidString,
                storeName: receipt.storeName,
                date: ISO8601DateFormatter().string(from: receipt.date),
                total: (receipt.total as NSDecimalNumber).doubleValue,
                currency: receipt.currency,
                lineItems: receipt.lineItems.map { item in
                    ExportLineItem(
                        productName: item.productName,
                        price: (item.price as NSDecimalNumber).doubleValue,
                        category: item.category.rawValue
                    )
                }
            )
        }

        let export = ExportData(receipts: exportReceipts)

        if let jsonData = try? encoder.encode(export),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            exportData = jsonString
            showExportSheet = true
        }
    }
}

// MARK: - Export Models

private struct ExportData: Codable {
    let exportedAt: String
    let receiptCount: Int
    let receipts: [ExportReceipt]

    init(receipts: [ExportReceipt]) {
        self.exportedAt = ISO8601DateFormatter().string(from: Date())
        self.receiptCount = receipts.count
        self.receipts = receipts
    }
}

private struct ExportReceipt: Codable {
    let id: String
    let storeName: String
    let date: String
    let total: Double
    let currency: String
    let lineItems: [ExportLineItem]
}

private struct ExportLineItem: Codable {
    let productName: String
    let price: Double
    let category: String
}

/// Simple share sheet for exporting JSON data.
private struct ExportView: View {
    let data: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    Text(data)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))
                .padding()

                ShareLink(
                    item: data,
                    subject: Text("BonScanner Export"),
                    message: Text("Date exportate din BonScanner")
                ) {
                    Label("Distribuie", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gata") { dismiss() }
                }
            }
        }
    }
}
