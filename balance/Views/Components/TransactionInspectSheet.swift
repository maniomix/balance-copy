import SwiftUI

// MARK: - Transaction Inspect Sheet (Full)

struct TransactionInspectSheet: View {
    let transaction: Transaction
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showAttachment = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Header Card - Category & Type
                        DS.Card {
                            HStack(spacing: 16) {
                                Circle()
                                    .fill(transaction.category.tint.opacity(0.2))
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: transaction.category.icon)
                                            .foregroundStyle(transaction.category.tint)
                                            .font(.system(size: 24, weight: .semibold))
                                    )

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(transaction.category.title)
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(DS.Colors.text)

                                    HStack(spacing: 8) {
                                        Image(systemName: transaction.type.icon)
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(transaction.type.title)
                                            .font(.system(size: 14, weight: .semibold))
                                    }
                                    .foregroundStyle(transaction.type == .income ? .green : DS.Colors.subtext)
                                }

                                Spacer()
                            }
                        }

                        // Amount Card
                        DS.Card {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Amount")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)

                                Text(
                                    transaction.type == .expense ?
                                    AttributedString("-") + DS.Format.moneyAttributed(transaction.amount) :
                                    AttributedString("+") + DS.Format.moneyAttributed(transaction.amount)
                                )
                                .font(.system(size: 40, weight: .bold, design: .rounded))
                                .foregroundStyle(transaction.type == .income ? .green : DS.Colors.text)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Details Card
                        DS.Card {
                            VStack(alignment: .leading, spacing: 16) {
                                SectionHeader(title: "Details")

                                InspectDetailRow(
                                    icon: "calendar",
                                    title: "Date & Time",
                                    value: formatDate(transaction.date)
                                )

                                InspectDetailRow(
                                    icon: transaction.paymentMethod.icon,
                                    title: "Payment Method",
                                    value: transaction.paymentMethod.displayName
                                )
                            }
                        }

                        // Shared / Split Card
                        if let split = HouseholdManager.shared.splitExpense(for: transaction.id) {
                            DS.Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Shared Expense")

                                    HStack(spacing: 8) {
                                        Image(systemName: "person.2.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(DS.Colors.accent)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Split: \(split.splitRule.displayName)")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(DS.Colors.text)

                                            Text(split.isSettled ? "Settled" : "Unsettled")
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundStyle(split.isSettled ? DS.Colors.positive : DS.Colors.warning)
                                        }

                                        Spacer()

                                        if !split.isSettled {
                                            Text("Open")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(DS.Colors.warning)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(DS.Colors.warning.opacity(0.1), in: Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        // Note Card
                        if !transaction.note.isEmpty {
                            DS.Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Note")

                                    Text(transaction.note)
                                        .font(.system(size: 15, weight: .regular))
                                        .foregroundStyle(DS.Colors.text)
                                        .lineLimit(nil)
                                }
                            }
                        }

                        // Attachment Card
                        if transaction.attachmentData != nil, let type = transaction.attachmentType {
                            DS.Card {
                                VStack(alignment: .leading, spacing: 12) {
                                    SectionHeader(title: "Attachment")

                                    Button {
                                        showAttachment = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "paperclip")
                                                .font(.system(size: 16, weight: .semibold))
                                                .foregroundStyle(.blue)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(type == .image ? "Image" : "PDF Document")
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .foregroundStyle(DS.Colors.text)

                                                Text("Tap to view")
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundStyle(DS.Colors.subtext)
                                            }

                                            Spacer()

                                            Image(systemName: "chevron.right")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(DS.Colors.subtext)
                                        }
                                        .padding(12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .fill(DS.Colors.surface2)
                                        )
                                    }
                                }
                            }
                        }

                        // ID Card (for debug)
                        DS.Card {
                            VStack(alignment: .leading, spacing: 12) {
                                SectionHeader(title: "Transaction ID")

                                Text(transaction.id.uuidString)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Inspect Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
            .sheet(isPresented: $showAttachment) {
                if let data = transaction.attachmentData, let type = transaction.attachmentType {
                    AttachmentViewer(attachmentData: data, attachmentType: type)
                }
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(DS.Colors.subtext)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

// MARK: - Inspect Detail Row

struct InspectDetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(DS.Colors.surface2)
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Colors.text.opacity(0.7))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)

                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
            }

            Spacer()
        }
    }
}

// MARK: - Transaction Inspect Preview

struct TransactionInspectPreview: View {
    let transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(transaction.category.tint.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: transaction.category.icon)
                            .foregroundStyle(transaction.category.tint)
                            .font(.system(size: 20, weight: .semibold))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(transaction.category.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Colors.text)

                    Text(transaction.type.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(transaction.type == .income ? .green : DS.Colors.subtext)
                }

                Spacer()
            }

            HStack {
                Text(
                    transaction.type == .expense ?
                    AttributedString("-") + DS.Format.moneyAttributed(transaction.amount) :
                    AttributedString("+") + DS.Format.moneyAttributed(transaction.amount)
                )
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(transaction.type == .income ? .green : DS.Colors.text)

                Spacer()
            }

            Divider()
                .background(DS.Colors.grid)

            VStack(alignment: .leading, spacing: 12) {
                DetailRow(
                    icon: "calendar",
                    title: "Date",
                    value: formatDate(transaction.date)
                )

                DetailRow(
                    icon: transaction.paymentMethod.icon,
                    title: "Payment",
                    value: transaction.paymentMethod.displayName
                )

                if !transaction.note.isEmpty {
                    DetailRow(
                        icon: "note.text",
                        title: "Note",
                        value: transaction.note,
                        maxLines: 2
                    )
                }

                if transaction.attachmentData != nil {
                    DetailRow(
                        icon: "paperclip",
                        title: "Attachment",
                        value: "\u{1F4CE} \(transaction.attachmentType?.rawValue.capitalized ?? "File")"
                    )
                }
            }
        }
        .padding(20)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DS.Colors.surface)
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    var maxLines: Int? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)

                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(maxLines)
            }
        }
    }
}

// MARK: - Attachment Viewer

struct AttachmentViewer: View {
    let attachmentData: Data
    let attachmentType: AttachmentType
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ZStack {
                    DS.Colors.bg.ignoresSafeArea()

                    if attachmentType == .image, let uiImage = UIImage(data: attachmentData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
                                        }
                                        .onEnded { _ in
                                            lastScale = scale
                                            if scale < 1.0 {
                                                withAnimation(.spring(response: 0.3)) {
                                                    scale = 1.0
                                                    lastScale = 1.0
                                                    offset = .zero
                                                    lastOffset = .zero
                                                }
                                            }
                                            if scale > 4.0 {
                                                withAnimation(.spring(response: 0.3)) {
                                                    scale = 4.0
                                                    lastScale = 4.0
                                                }
                                            }
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.0 {
                                                let maxOffsetX = (geometry.size.width * (scale - 1)) / 2
                                                let maxOffsetY = (geometry.size.height * (scale - 1)) / 2

                                                var newX = lastOffset.width + value.translation.width
                                                var newY = lastOffset.height + value.translation.height

                                                newX = min(max(newX, -maxOffsetX), maxOffsetX)
                                                newY = min(max(newY, -maxOffsetY), maxOffsetY)

                                                offset = CGSize(width: newX, height: newY)
                                            }
                                        }
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring(response: 0.3)) {
                                    scale = 1.0
                                    lastScale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                            .padding()
                    } else {
                        VStack(spacing: 20) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(DS.Colors.accent)

                            Text("Document")
                                .font(DS.Typography.title)
                                .foregroundStyle(DS.Colors.text)

                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(attachmentData.count), countStyle: .file))")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }
            }
            .navigationTitle("Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }
}

// MARK: - URL Identifiable

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
