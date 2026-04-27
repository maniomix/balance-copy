import SwiftUI
import PhotosUI

// ============================================================
// MARK: - AI Receipt Scanner View
// ============================================================
//
// Photo picker + camera for receipt scanning.
// Shows parsed results with confirm/edit before adding.
//
// ============================================================

struct AIReceiptScannerView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var scanner = AIReceiptScanner.shared
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var scannedImage: UIImage?
    @State private var showCamera = false
    @State private var showConfirm = false

    // Editable fields after scan
    @State private var editAmount: String = ""
    @State private var editMerchant: String = ""
    @State private var editCategory: Category = .other
    @State private var editDate: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if scanner.isScanning {
                    scanningView
                } else if let result = scanner.lastResult, showConfirm {
                    confirmView(result)
                } else {
                    pickerView
                }
            }
            .padding()
            .background(DS.Colors.bg)
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView { image in
                    if let image {
                        scannedImage = image
                        startScan(image: image)
                    }
                }
            }
            .onChange(of: selectedPhoto) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        scannedImage = image
                        startScan(image: image)
                    }
                }
            }
        }
    }

    // MARK: - Picker View

    private var pickerView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 60))
                .foregroundStyle(DS.Colors.accent)

            Text("Scan a Receipt")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text("Take a photo or choose from your library. We'll extract the amount, merchant, and date automatically.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                Button {
                    showCamera = true
                } label: {
                    HStack {
                        Image(systemName: "camera.fill")
                        Text("Take Photo")
                    }
                    .font(DS.Typography.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Choose from Library")
                    }
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Colors.accent, lineWidth: 1.5)
                    )
                }
            }

            if let error = scanner.errorMessage {
                Text(error)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.danger)
            }

            Spacer()
        }
    }

    // MARK: - Scanning View

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Scanning receipt...")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
            Spacer()
        }
    }

    // MARK: - Confirm View

    private func confirmView(_ result: ReceiptData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Preview image thumbnail
                if let img = scannedImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                }

                DS.Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Scanned Data")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)

                        Divider().foregroundStyle(DS.Colors.grid)

                        // Merchant
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Merchant")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            TextField("Merchant name", text: $editMerchant)
                                .font(DS.Typography.body)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Amount
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Amount")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            TextField("0.00", text: $editAmount)
                                .font(DS.Typography.body)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                        }

                        // Date
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Date")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            DatePicker("", selection: $editDate, displayedComponents: .date)
                                .labelsHidden()
                        }

                        // Category
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Category")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Picker("Category", selection: $editCategory) {
                                ForEach(store.allCategories, id: \.self) { cat in
                                    Text(cat.title).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            .tint(DS.Colors.accent)
                        }
                    }
                }

                // Line items
                if !result.lineItems.isEmpty {
                    DS.Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Line Items")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)

                            ForEach(result.lineItems) { item in
                                HStack {
                                    Text(item.description)
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Text(String(format: "$%.2f", Double(item.amount) / 100.0))
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        scanner.lastResult = nil
                        showConfirm = false
                        selectedPhoto = nil
                    } label: {
                        Text("Rescan")
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DS.Colors.subtext.opacity(0.3), lineWidth: 1)
                            )
                    }

                    Button {
                        addTransaction()
                    } label: {
                        Text("Add Transaction")
                            .font(DS.Typography.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startScan(image: UIImage) {
        Task {
            if let result = await scanner.scan(image: image) {
                // Populate editable fields
                editMerchant = result.merchantName ?? ""
                if let amount = result.totalAmount {
                    editAmount = String(format: "%.2f", Double(amount) / 100.0)
                }
                editDate = result.date ?? Date()

                // Auto-suggest category from merchant name
                if let merchant = result.merchantName,
                   let suggested = AICategorySuggester.shared.suggest(note: merchant) {
                    editCategory = suggested
                }

                showConfirm = true
            }
        }
    }

    private func addTransaction() {
        let amountCents: Int
        if let value = Double(editAmount.replacingOccurrences(of: ",", with: ".")) {
            amountCents = Int(value * 100)
        } else {
            return
        }

        let txn = Transaction(
            amount: amountCents,
            date: editDate,
            category: editCategory,
            note: editMerchant.isEmpty ? "Receipt scan" : editMerchant,
            paymentMethod: .card,
            type: .expense
        )
        store.add(txn)

        // Learn from this
        if !editMerchant.isEmpty {
            AICategorySuggester.shared.learn(note: editMerchant, category: editCategory)
        }

        // Event insight
        AIInsightEngine.shared.onTransactionAdded(txn, store: store)

        Haptics.success()
        dismiss()
    }
}

// MARK: - Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) { self.onCapture(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onCapture(nil) }
        }
    }
}
