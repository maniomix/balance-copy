import SwiftUI

// MARK: - Transaction Sheet (unified Add + Edit host)
//
// Phase 5 of the Add Transaction rebuild. One sheet hosts both flows:
//
//   TransactionSheet(.add(initialMonth:), in: $store, source: .dashboardFAB)
//   TransactionSheet(.edit(transactionID:), in: $store, source: .manual)
//
// Internally it owns:
//   - the `TransactionDraftStore`
//   - the `TransactionForm` view
//   - nav chrome (Cancel + Save)
//   - the category editor sheet
//   - the attachment confirmation dialog + image/document pickers
//   - the post-save allocation preview sheet (income only)
//   - the Edit-mode delete button
//
// Save funnels through `TransactionDraftCommitter` so call-site code shrinks
// to just presenting an instance of this view.

enum TransactionSheetKind {
    /// Brand-new transaction. `initialMonth` controls the default date — see
    /// `TransactionDraft.newDraft(initialMonth:source:)`.
    case add(initialMonth: Date,
             accountId: UUID? = nil,
             linkedGoalId: UUID? = nil,
             type: TransactionType = .expense)
    /// Edit an existing transaction by ID. Hydrates the draft from
    /// `store.transactions` on appear.
    case edit(transactionID: UUID)
}

struct TransactionSheet: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var store: Store
    let kind: TransactionSheetKind
    let source: TransactionDraftSource

    @StateObject private var draftStore: TransactionDraftStore

    // Sheet state
    @State private var showAddCategory = false
    @State private var editingCustomCategory: CustomCategoryModel?
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var showAttachmentOptions = false
    @State private var showSaveFailedAlert = false
    @State private var showDeleteConfirm = false
    @State private var showAttachmentTooLargeAlert = false

    // Allocation preview (income-only follow-up).
    @State private var pendingProposals: [AllocationProposal] = []
    @State private var showAllocationPreview = false

    // Tracks whether the original transaction was found on appear (edit only).
    @State private var didHydrate = false

    init(_ kind: TransactionSheetKind,
         in store: Binding<Store>,
         source: TransactionDraftSource = .manual) {
        self._store = store
        self.kind = kind
        self.source = source

        // Construct the draft store synchronously from `kind`. For `.edit` we
        // can't peek at the bound store here (it's a Binding), so we seed an
        // empty placeholder draft and hydrate from `store.transactions` on
        // `.onAppear`. This keeps the init pure.
        let initialDraft: TransactionDraft
        let mode: TransactionDraftMode
        switch kind {
        case .add(let initialMonth, let accountId, let goalId, let type):
            initialDraft = .newDraft(
                initialMonth: initialMonth,
                source: source,
                accountId: accountId,
                linkedGoalId: goalId,
                type: type
            )
            mode = .add
        case .edit:
            // Placeholder — replaced in `hydrateForEdit`.
            initialDraft = .newDraft(initialMonth: Date(), source: source)
            mode = .add
        }
        _draftStore = StateObject(wrappedValue: TransactionDraftStore(
            mode: mode,
            initial: initialDraft
        ))
    }

    var body: some View {
        NavigationView {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        TransactionForm(
                            draftStore: draftStore,
                            store: $store,
                            onAddCategory: { showAddCategory = true },
                            onEditCategory: { editingCustomCategory = $0 },
                            onPickAttachment: { showAttachmentOptions = true }
                        )

                        if draftStore.mode.isEdit {
                            deleteButton
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .keyboardManagement()
        }
        .onAppear(perform: onAppearSetup)
        .confirmationDialog("Add attachment", isPresented: $showAttachmentOptions) {
            Button("Attach Photo")    { showImagePicker = true }
            Button("Attach File")     { showDocumentPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddCategory) {
            FullCategoryEditor(
                customCategories: $store.customCategoriesWithIcons,
                onSave: { newCategory in
                    if !store.customCategoriesWithIcons.contains(where: { $0.id == newCategory.id }) {
                        store.customCategoriesWithIcons.append(newCategory)
                    }
                    draftStore.draft.category = .custom(newCategory.name)
                    Task { try? await SupabaseManager.shared.saveStore(store) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingCustomCategory) { customCat in
            FullCategoryEditor(
                customCategories: $store.customCategoriesWithIcons,
                editingCategory: customCat,
                onSave: { category in
                    if let i = store.customCategoriesWithIcons.firstIndex(where: { $0.id == category.id }) {
                        store.customCategoriesWithIcons[i] = category
                    }
                    Task { try? await SupabaseManager.shared.saveStore(store) }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showImagePicker, onDismiss: enforceAttachmentLimit) {
            ImagePicker(
                imageData: $draftStore.draft.attachmentData,
                attachmentType: $draftStore.draft.attachmentType
            )
        }
        .sheet(isPresented: $showDocumentPicker, onDismiss: enforceAttachmentLimit) {
            DocumentPicker(
                fileData: $draftStore.draft.attachmentData,
                attachmentType: $draftStore.draft.attachmentType
            )
        }
        .alert("Attachment Too Large", isPresented: $showAttachmentTooLargeAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Attachments must be 10 MB or smaller. The file was not added.")
        }
        .alert("Save Failed", isPresented: $showSaveFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(draftStore.mode.isEdit
                 ? "Your changes could not be saved. Please try again."
                 : "Your transaction could not be saved. Please try again.")
        }
        .alert("Delete Transaction?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: confirmDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone from here. Linked goal contributions and recurring matches will also be cleaned up.")
        }
        .sheet(isPresented: $showAllocationPreview, onDismiss: {
            pendingProposals = []
            dismiss()
        }) {
            if let savedTx = lastSavedTransaction {
                AllocationPreviewSheet(
                    transaction: savedTx,
                    proposals: pendingProposals,
                    onApplied: {}
                )
            }
        }
    }

    // MARK: - Derived

    private var navTitle: String {
        draftStore.mode.isEdit ? "Edit Transaction" : "Add Transaction"
    }

    private var canSave: Bool {
        let hasAccounts = !AccountManager.shared.accounts.isEmpty
        return draftStore.canSave(hasAccounts: hasAccounts)
    }

    /// The transaction we just saved (used to feed `AllocationPreviewSheet`).
    /// Reading from `store.transactions` keeps it in sync with what
    /// `TransactionService.performAdd` actually wrote.
    private var lastSavedTransaction: Transaction? {
        store.transactions.first(where: { $0.id == draftStore.draft.id })
    }

    // MARK: - Lifecycle

    private func onAppearSetup() {
        if case .edit(let id) = kind, !didHydrate {
            hydrateForEdit(id: id)
            didHydrate = true
        }

        if case .add = kind {
            draftStore.applyDefaults(from: store)
        }

        draftStore.refreshSuggestions(in: store)
    }

    private func hydrateForEdit(id: UUID) {
        guard let tx = store.transactions.first(where: { $0.id == id }) else {
            // Original gone — close the sheet on the next runloop tick.
            DispatchQueue.main.async { dismiss() }
            return
        }
        // Replace the placeholder store. `@StateObject` won't reinitialise, so
        // mutate the existing one in place: its `mode` / `initialDraft` need
        // to reflect the actual original. We rebuild a fresh store and assign
        // its values onto the existing one.
        let hydrated = TransactionDraft.from(tx, source: source)
        draftStore.draft = hydrated
        draftStore.mode = .edit(original: tx)
    }

    // MARK: - Actions

    private func save() {
        let result: DraftCommitResult = {
            var local = store
            let r = TransactionDraftCommitter.commit(draftStore: draftStore, appStore: &local)
            store = local
            return r
        }()

        switch result {
        case .saved, .noChange:
            dismiss()
        case .savedWithProposals(let proposals):
            pendingProposals = proposals
            // Defer presentation by a tick so the save's haptic + animation
            // settle before the allocation sheet pops.
            DispatchQueue.main.async { showAllocationPreview = true }
        case .localSaveFailed:
            showSaveFailedAlert = true
        case .validationFailed:
            // Form already surfaces the issue inline; the Save button should
            // have been disabled. Stay open.
            Haptics.warning()
        }
    }

    /// Reject an oversize attachment immediately rather than letting save-time
    /// validation surface it. The 10 MB ceiling matches `TransactionDraft`'s
    /// `maxAttachmentBytes`. Picker callbacks already populated the draft, so
    /// we clear it back out before showing the alert.
    private func enforceAttachmentLimit() {
        guard let data = draftStore.draft.attachmentData else { return }
        let limit = 10 * 1024 * 1024
        if data.count > limit {
            draftStore.clearAttachment()
            showAttachmentTooLargeAlert = true
            Haptics.warning()
        }
    }

    private func confirmDelete() {
        guard case .edit(let original) = draftStore.mode else { return }
        var local = store
        _ = TransactionService.performDelete(original, store: &local)
        store = local
        Haptics.success()
        dismiss()
    }

    // MARK: - Delete button (edit mode)

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Delete Transaction")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(DS.Colors.danger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                DS.Colors.danger.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

