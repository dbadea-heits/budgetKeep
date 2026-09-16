import SwiftUI
import SwiftData

/// Review screen shown after OCR processing. User can correct parsed fields before saving.
struct ReceiptReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let parsedReceipt: ParsedReceipt
    let receiptImage: UIImage?
    var editingReceipt: Receipt? // nil when creating new, set when editing existing

    // Editable fields
    @State private var storeName: String
    @State private var receiptDate: Date
    @State private var lineItems: [EditableLineItem]
    @State private var showRawText = false

    init(parsedReceipt: ParsedReceipt, receiptImage: UIImage?, editingReceipt: Receipt? = nil) {
        self.parsedReceipt = parsedReceipt
        self.receiptImage = receiptImage
        self.editingReceipt = editingReceipt

        _storeName = State(initialValue: parsedReceipt.storeName ?? "Magazin necunoscut")
        _receiptDate = State(initialValue: parsedReceipt.date ?? Date())

        // Convert parsed line items to editable form, auto-categorizing
        let items = parsedReceipt.lineItems.map { parsed in
            EditableLineItem(
                id: UUID(),
                productName: parsed.productName,
                price: parsed.price,
                category: Categorizer.categorize(parsed.productName)
            )
        }
        _lineItems = State(initialValue: items.isEmpty ? [EditableLineItem(productName: "", price: 0)] : items)
    }

    var body: some View {
        Form {
            // Header section
            Section("Bon Scanat") {
                HStack {
                    Text("Magazin")
                    Spacer()
                    TextField("Nume magazin", text: $storeName)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Data", selection: $receiptDate, displayedComponents: .date)

                if let total = parsedReceipt.total {
                    HStack {
                        Text("Total detectat")
                        Spacer()
                        Text(Formatting.price(total))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Image preview
            if let image = receiptImage {
                Section("Imagine") {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .cornerRadius(8)
                }
            }

            // Line items
            Section("Produse") {
                ForEach($lineItems) { $item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Produs", text: $item.productName)
                                .font(.body)
                            Spacer()
                            TextField("Preț", value: $item.price, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }

                        // Category picker
                        HStack {
                            Text(item.category.icon)
                            Picker("", selection: $item.category) {
                                ForEach(Category.allCases) { cat in
                                    Text(cat.displayName).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            Spacer()
                        }
                    }
                }
                .onDelete { indices in
                    lineItems.remove(atOffsets: indices)
                }

                Button {
                    lineItems.append(EditableLineItem(productName: "", price: 0))
                } label: {
                    Label("Adaugă produs", systemImage: "plus.circle")
                }
            }

            // Raw OCR text (expandable)
            Section {
                Button {
                    withAnimation { showRawText.toggle() }
                } label: {
                    HStack {
                        Text("Text OCR brut")
                        Spacer()
                        Image(systemName: showRawText ? "chevron.up" : "chevron.down")
                    }
                }

                if showRawText {
                    Text(parsedReceipt.rawText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }

            // Save
            Section {
                Button(action: saveReceipt) {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                        Text("Salvează Bonul")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .tint(.green)
                .disabled(storeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Revizuiește")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveReceipt() {
        let receipt: Receipt

        if let existing = editingReceipt {
            // Update existing
            receipt = existing
            receipt.storeName = storeName
            receipt.date = receiptDate
            // Remove old line items
            for item in receipt.lineItems {
                modelContext.delete(item)
            }
            receipt.lineItems.removeAll()
        } else {
            // Create new
            receipt = Receipt(
                storeName: storeName,
                date: receiptDate,
                rawOcrText: parsedReceipt.rawText
            )
            modelContext.insert(receipt)

            // Save image if we have one
            if let image = receiptImage {
                let path = OCRService.saveImage(image, receiptID: receipt.id)
                receipt.imagePath = path
            }
        }

        // Add line items
        for item in lineItems where !item.productName.trimmingCharacters(in: .whitespaces).isEmpty {
            let li = LineItem(
                productName: item.productName.trimmingCharacters(in: .whitespaces),
                price: item.price,
                category: item.category,
                receipt: receipt
            )
            receipt.lineItems.append(li)
        }

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Editable Line Item

struct EditableLineItem: Identifiable {
    let id: UUID
    var productName: String
    var price: Decimal
    var category: Category

    init(id: UUID = UUID(), productName: String, price: Decimal, category: Category = .other) {
        self.id = id
        self.productName = productName
        self.price = price
        self.category = category
    }
}
