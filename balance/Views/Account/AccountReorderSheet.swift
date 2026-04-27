import SwiftUI

// Modal reorder for active accounts. Edits a local copy, persists on Done.
struct AccountReorderSheet: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var accountManager = AccountManager.shared
    @State private var working: [Account] = []
    @State private var saving = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(working) { account in
                        HStack(spacing: 12) {
                            Image(systemName: account.type.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AccountColorTag.color(for: account.colorTag))
                                .frame(width: 30, height: 30)
                                .background(
                                    AccountColorTag.color(for: account.colorTag).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                            Text(account.name)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text(account.type.displayName)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .onMove(perform: move)
                } header: {
                    Text("Drag to reorder")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await save() } } label: {
                        if saving { ProgressView() } else { Text("Done").fontWeight(.semibold) }
                    }
                    .disabled(saving)
                }
            }
            .onAppear {
                working = AccountManager.sortByDisplayOrder(accountManager.activeAccounts)
            }
        }
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        working.move(fromOffsets: offsets, toOffset: destination)
    }

    private func save() async {
        saving = true
        _ = await accountManager.reorder(working.map(\.id))
        saving = false
        dismiss()
    }
}
