import SwiftUI

/// Initial scan screen: offers camera capture, photo library pick, or manual entry.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var showManualEntry = false
    @State private var capturedImage: UIImage?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    // Navigation: after OCR processing, show review
    @State private var showReview = false
    @State private var parsedReceipt: ParsedReceipt?

    private let ocrService = OCRService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App icon / branding
                VStack(spacing: 12) {
                    Text("🧾")
                        .font(.system(size: 72))
                    Text("BonScanner")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Scanează bonuri fiscale românești")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Main action buttons
                VStack(spacing: 16) {
                    scanButton(
                        title: "Scanează cu Camera",
                        icon: "camera.fill",
                        color: .blue
                    ) {
                        showCamera = true
                    }

                    scanButton(
                        title: "Alege din Galerie",
                        icon: "photo.on.rectangle",
                        color: .green
                    ) {
                        showPhotoLibrary = true
                    }

                    scanButton(
                        title: "Adaugă Manual",
                        icon: "pencil.and.list.clipboard",
                        color: .orange
                    ) {
                        showManualEntry = true
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Error display
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding()
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, selectedImage: $capturedImage)
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(sourceType: .photoLibrary, selectedImage: $capturedImage)
            }
            .onChange(of: capturedImage) { _, newImage in
                guard let image = newImage else { return }
                processImage(image)
            }
            .navigationDestination(isPresented: $showReview) {
                if let parsed = parsedReceipt, let image = capturedImage {
                    ReceiptReviewView(
                        parsedReceipt: parsed,
                        receiptImage: image
                    )
                }
            }
            .navigationDestination(isPresented: $showManualEntry) {
                ManualReceiptEntryView()
            }
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Procesez bonul...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(24)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                }
            }
        }
    }

    private func scanButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 14))
            .foregroundColor(.white)
        }
        .disabled(isProcessing)
    }

    private func processImage(_ image: UIImage) {
        isProcessing = true
        errorMessage = nil

        Task {
            do {
                // Resize for OCR
                let prepared = OCRService.prepareImage(image) ?? image
                let rawText = try await ocrService.recognizeText(from: prepared)
                let parsed = ReceiptParser.parse(rawText)

                await MainActor.run {
                    parsedReceipt = parsed
                    showReview = true
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                    capturedImage = nil
                }
            }
        }
    }
}

/// Manual receipt entry (no photo needed).
struct ManualReceiptEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var storeName = ""
    @State private var date = Date()
    @State private var productName = ""
    @State private var productPrice = ""
    @State private var lineItems: [(name: String, price: Decimal)] = []
    @State private var showAddItem = false

    var body: some View {
        Form {
            Section("Magazin") {
                TextField("Denumire magazin", text: $storeName)
                DatePicker("Data", selection: $date, displayedComponents: .date)
            }

            Section("Produse") {
                if lineItems.isEmpty {
                    Text("Nu ai adăugat niciun produs încă.")
                        .foregroundColor(.secondary)
                }

                ForEach(lineItems.indices, id: \.self) { index in
                    HStack {
                        Text(lineItems[index].name)
                        Spacer()
                        Text(Formatting.price(lineItems[index].price))
                    }
                }
                .onDelete { indices in
                    lineItems.remove(atOffsets: indices)
                }

                Button {
                    showAddItem = true
                } label: {
                    Label("Adaugă produs", systemImage: "plus.circle")
                }
            }

            Section {
                Button("Salvează Bonul") {
                    saveReceipt()
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .disabled(storeName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Adaugă Manual")
        .alert("Adaugă produs", isPresented: $showAddItem) {
            TextField("Denumire", text: $productName)
            TextField("Preț", text: $productPrice)
                .keyboardType(.decimalPad)
            Button("Adaugă") { addItem() }
            Button("Anulează", role: .cancel) {
                productName = ""
                productPrice = ""
            }
        } message: {
            Text("Introdu denumirea produsului și prețul")
        }
    }

    private func addItem() {
        guard !productName.trimmingCharacters(in: .whitespaces).isEmpty,
              let price = Decimal(string: productPrice.replacingOccurrences(of: ",", with: ".")) else {
            return
        }
        lineItems.append((name: productName, price: price))
        productName = ""
        productPrice = ""
    }

    private func saveReceipt() {
        guard !storeName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        let receipt = Receipt(
            storeName: storeName.trimmingCharacters(in: .whitespaces),
            date: date
        )
        receipt.lineItems = lineItems.map { item in
            let li = LineItem(productName: item.name, price: item.price)
            li.receipt = receipt
            li.category = Categorizer.categorize(item.name)
            return li
        }
        modelContext.insert(receipt)
        try? modelContext.save()
        dismiss()
    }
}
