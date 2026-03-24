import SwiftUI

// MARK: - PDF Export View (Legacy Wrapper)
// Now redirects to the full ReportExportView.
// Kept for backward compatibility if referenced elsewhere.

struct PDFExportView: View {
    @State private var store = Store()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ReportExportView(store: $store)
    }
}
