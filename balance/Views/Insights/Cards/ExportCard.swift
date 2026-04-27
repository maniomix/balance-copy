import SwiftUI

struct ExportCard: View {
    let onExcel: () -> Void
    let onCSV: () -> Void
    let onPDF: () -> Void

    @State private var showFormatSheet = false

    var body: some View {
        Button {
            Haptics.light()
            showFormatSheet = true
        } label: {
            DS.Card {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(DS.Colors.surface2)
                            .frame(width: 36, height: 36)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Export")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                        Text("Share this month as Excel, CSV, or PDF")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export this month")
        .accessibilityHint("Choose Excel, CSV, or PDF format")
        .accessibilityAddTraits(.isButton)
        .confirmationDialog("Export format", isPresented: $showFormatSheet, titleVisibility: .visible) {
            Button("Excel (.xlsx)") {
                Haptics.medium()
                onExcel()
            }
            Button("CSV (.csv)") {
                Haptics.medium()
                onCSV()
            }
            Button("PDF Report") {
                Haptics.medium()
                onPDF()
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
