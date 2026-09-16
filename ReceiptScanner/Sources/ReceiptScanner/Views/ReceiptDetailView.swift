import SwiftUI
import SwiftData

/// Full receipt breakdown with categorized items grouped by category.
struct ReceiptDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let receipt: Receipt

    @State private var showEdit = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            // Header
            Section {
                VStack(spacing: 8) {
                    Text("🏪")
                        .font(.system(size: 48))

                    Text(receipt.storeName)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(receipt.formattedDateTime)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(receipt.formattedTotal)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.top, 4)

                    Text("\(receipt.itemCount) produse")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Receipt image if available
            if let imagePath = receipt.imagePath,
               let image = OCRService.loadImage(from: imagePath) {
                Section("Imagine") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(8)
                }
            }

            // Items grouped by category
            ForEach(receipt.itemsByCategory, id: \.0) { category, items in
                Section {
                    ForEach(items) { item in
                        LineItemRow(item: item)
                    }
                } header: {
                    HStack {
                        Text(category.icon)
                        Text(category.displayName)
                            .font(.subheadline)
                        Spacer()
                        Text(Formatting.price(items.reduce(Decimal.zero) { $0 + $1.price }))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Raw OCR text
            if !receipt.rawOcrText.isEmpty {
                Section("Text OCR") {
                    Text(receipt.rawOcrText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Detalii Bon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showEdit = true
                    } label: {
                        Label("Editează", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Șterge", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            // Pass existing receipt data back through review screen
            editSheet
        }
        .alert("Șterge bonul?", isPresented: $showDeleteConfirmation) {
            Button("Șterge", role: .destructive) { deleteReceipt() }
            Button("Anulează", role: .cancel) {}
        } message: {
            Text("Această acțiune nu poate fi anulată.")
        }
    }

    private var editSheet: some View {
        let parsed = ParsedReceipt(
            storeName: receipt.storeName,
            date: receipt.date,
            total: receipt.total,
            paymentMethod: nil,
            lineItems: receipt.lineItems.map {
                ParsedLineItem(productName: $0.productName, quantity: 1, price: $0.price)
            },
            rawText: receipt.rawOcrText
        )
        let image = receipt.imagePath.flatMap { OCRService.loadImage(from: $0) }

        return NavigationStack {
            ReceiptReviewView(
                parsedReceipt: parsed,
                receiptImage: image,
                editingReceipt: receipt
            )
        }
    }

    private func deleteReceipt() {
        if let path = receipt.imagePath {
            OCRService.deleteImage(at: path)
        }
        modelContext.delete(receipt)
        try? modelContext.save()
        dismiss()
    }
}

/// A single line item row showing product name, price, and category badge.
struct LineItemRow: View {
    let item: LineItem

    var body: some View {
        HStack {
            // Category emoji badge
            Text(item.category.icon)
                .font(.caption)
                .padding(6)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.productName)
                    .font(.body)
                    .lineLimit(2)
                Text(item.category.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(item.formattedPrice)
                .font(.body)
                .fontWeight(.medium)
        }
        .padding(.vertical, 2)
    }
}
