import SwiftUI
import SwiftData

/// Chronological list of all saved receipts.
struct ReceiptListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]

    @State private var showScanner = false
    @State private var searchText = ""
    @State private var selectedReceipt: Receipt?

    var body: some View {
        NavigationStack {
            Group {
                if receipts.isEmpty {
                    emptyState
                } else {
                    List {
                        // Monthly summary header
                        Section {
                            monthlySummary
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }

                        ForEach(filteredReceipts) { receipt in
                            NavigationLink {
                                ReceiptDetailView(receipt: receipt)
                            } label: {
                                ReceiptRowView(receipt: receipt)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deleteReceipt(receipt)
                                } label: {
                                    Label("Șterge", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bonuri")
            .searchable(text: $searchText, prompt: "Caută magazin sau produs...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                ScanView()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Niciun bon", systemImage: "receipt")
        } description: {
            Text("Scanează primul tău bon fiscal românesc pentru a începe.")
        } actions: {
            Button("Scanează Bon") {
                showScanner = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var monthlySummary: some View {
        let thisMonth = Calendar.current.component(.month, from: Date())
        let thisYear = Calendar.current.component(.year, from: Date())
        let monthReceipts = receipts.filter {
            Calendar.current.component(.month, from: $0.date) == thisMonth &&
            Calendar.current.component(.year, from: $0.date) == thisYear
        }
        let total = monthReceipts.reduce(Decimal.zero) { $0 + $1.total }

        return HStack {
            VStack(alignment: .leading) {
                Text("Cheltuieli această lună")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text(Formatting.price(total))
                    .font(.title)
                    .fontWeight(.bold)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Bonuri")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("\(receipts.count)")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var filteredReceipts: [Receipt] {
        if searchText.isEmpty { return receipts }
        let query = searchText.lowercased()
        return receipts.filter { receipt in
            if receipt.storeName.lowercased().contains(query) { return true }
            for item in receipt.lineItems {
                if item.productName.lowercased().contains(query) { return true }
            }
            return false
        }
    }

    private func deleteReceipt(_ receipt: Receipt) {
        // Delete image if exists
        if let path = receipt.imagePath {
            OCRService.deleteImage(at: path)
        }
        modelContext.delete(receipt)
        try? modelContext.save()
    }
}

/// Single row in the receipt list.
struct ReceiptRowView: View {
    let receipt: Receipt

    var body: some View {
        HStack(spacing: 12) {
            // Store icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)
                Text("🏪")
                    .font(.title2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(receipt.storeName)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(receipt.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(receipt.itemCount) produse")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(receipt.formattedTotal)
                .fontWeight(.bold)
                .foregroundColor(.primary)
        }
        .padding(.vertical, 4)
    }
}
