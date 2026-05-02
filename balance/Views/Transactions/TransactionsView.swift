import SwiftUI
import Flow

// MARK: - Transactions

struct TransactionsView: View {
    @Binding var store: Store
    let goToBudget: () -> Void

    @State private var viewingAttachment: Transaction? = nil
    @State private var inspectingTransaction: Transaction? = nil  // ← جدید
    @State private var showAdd = false
    // @State private var showRecurring = false  // ← COMMENTED OUT - باگ داره
    @State private var search = ""
    @State private var searchScope: SearchScope = .thisMonth  // ← جدید
    @State private var showFilters = false
    @State private var filter = TransactionFilter()
    @State private var editingTxID: UUID? = nil
    @State private var showImport = false
    @State private var showRecurring = false  // ← دکمه Recurring
    @State private var sortOrder: TransactionSortOrder = .dateNewest  // ← Sort order

    // --- Multi-select state for Transactions screen ---
    @State private var isSelecting = false
    @State private var selectedTxIDs: Set<UUID> = []

    // --- Undo delete ---
    @State private var pendingUndo: [Transaction] = []
    @State private var showUndoBar: Bool = false
    @State private var undoWorkItem: DispatchWorkItem? = nil
    private let undoDelay: TimeInterval = 4.0
    private let undoAnim: Animation = .spring(response: 0.45, dampingFraction: 0.90)

    enum SearchScope: String, CaseIterable {
        case thisMonth = "This Month"
        case allTime = "All Time"
    }

    // Sort order for transactions
    enum TransactionSortOrder: String, CaseIterable {
        case dateNewest = "Newest First"
        case dateOldest = "Oldest First"
        case amountHighest = "Highest Amount"
        case amountLowest = "Lowest Amount"
        case categoryAZ = "Category A-Z"

        var icon: String {
            switch self {
            case .dateNewest: return "arrow.up.arrow.down.circle"
            case .dateOldest: return "arrow.up.arrow.down.circle"
            case .amountHighest: return "arrow.up.arrow.down.circle"
            case .amountLowest: return "arrow.up.arrow.down.circle"
            case .categoryAZ: return "arrow.up.arrow.down.circle"
            }
        }
    }

    private func scheduleUndoCommit() {
        undoWorkItem?.cancel()

        withAnimation(undoAnim) {
            showUndoBar = true
        }

        let item = DispatchWorkItem {
            withAnimation(undoAnim) {
                pendingUndo.removeAll()
                showUndoBar = false
            }
        }

        undoWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + undoDelay, execute: item)
    }

    private func undoDelete() {
        undoWorkItem?.cancel()
        withAnimation(uiAnim) {
            TransactionService.performUndo(pendingUndo, store: &store)
        }
        pendingUndo.removeAll()
        showUndoBar = false
    }

    private let uiAnim = Animation.spring(response: 0.35, dampingFraction: 0.9, blendDuration: 0.0)

    /// Cached filter+sort result. Was a computed property — body referenced
    /// it 5× per render (lines using `filtered.count`, `filtered.isEmpty`,
    /// the grouped/list paths), so every keystroke ran 5×O(n log n) work
    /// plus 1000+ `.lowercased()` String allocations per pass. Now computed
    /// once via `.onChange(of: filteredChangeKey)` and read 5× from state.
    @State private var filteredCache: [Transaction] = []

    private var filtered: [Transaction] { filteredCache }

    private struct FilteredChangeKey: Equatable {
        var search: String
        var scopeIsThisMonth: Bool
        var sortOrderRaw: String
        var filter: TransactionFilter
        var txSignature: Int
        var monthKey: String
    }

    private var filteredChangeKey: FilteredChangeKey {
        FilteredChangeKey(
            search: search,
            scopeIsThisMonth: searchScope == .thisMonth,
            sortOrderRaw: sortOrder.rawValue,
            filter: filter,
            txSignature: store.transactionsSignature,
            monthKey: Store.monthKey(store.selectedMonth)
        )
    }

    private func recomputeFiltered() {
        let sourceTx = searchScope == .thisMonth
            ? Analytics.monthTransactions(store: store)
            : store.transactions

        var out = sourceTx
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // `range(of:options:.caseInsensitive)` does no allocation per row;
            // the prior `.lowercased().contains` allocated two new Strings
            // per transaction per keystroke (~1000 allocs at 500 tx).
            out = out.filter {
                $0.note.range(of: trimmed, options: .caseInsensitive) != nil
                || $0.category.title.range(of: trimmed, options: .caseInsensitive) != nil
            }
        }

        out = filter.apply(to: out, allCategories: store.allCategories)

        switch sortOrder {
        case .dateNewest:    out.sort { $0.date > $1.date }
        case .dateOldest:    out.sort { $0.date < $1.date }
        case .amountHighest: out.sort { $0.amount > $1.amount }
        case .amountLowest:  out.sort { $0.amount < $1.amount }
        case .categoryAZ:    out.sort { $0.category.title.localizedStandardCompare($1.category.title) == .orderedAscending }
        }

        filteredCache = out
    }

    // Group transactions preserving their current order, splitting when the day changes
    private func groupConsecutiveByDay(_ txs: [Transaction]) -> [ConsecutiveDayGroup] {
        guard !txs.isEmpty else { return [] }

        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.locale = .current
        fmt.setLocalizedDateFormatFromTemplate("EEEE, MMM d")

        var groups: [ConsecutiveDayGroup] = []
        var currentDay = cal.startOfDay(for: txs[0].date)
        var currentItems: [Transaction] = []

        for tx in txs {
            let day = cal.startOfDay(for: tx.date)
            if day == currentDay {
                currentItems.append(tx)
            } else {
                groups.append(ConsecutiveDayGroup(
                    id: "\(currentDay.timeIntervalSince1970)-\(groups.count)",
                    day: currentDay,
                    title: fmt.string(from: currentDay),
                    items: currentItems
                ))
                currentDay = day
                currentItems = [tx]
            }
        }

        // Last group
        if !currentItems.isEmpty {
            groups.append(ConsecutiveDayGroup(
                id: "\(currentDay.timeIntervalSince1970)-\(groups.count)",
                day: currentDay,
                title: fmt.string(from: currentDay),
                items: currentItems
            ))
        }

        return groups
    }

    private var activeFilterCount: Int {
        filter.activeCount(allCategories: store.allCategories)
    }

    // --- Add state for pending delete confirmation (anchored to row)
    @State private var pendingDeleteID: UUID? = nil

    // Helper binding for single row delete confirmation dialog
    private var isRowDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { presenting in
                if !presenting { pendingDeleteID = nil }
            }
        )
    }

    // Helper binding for bulk delete confirmation dialog
    private var isBulkDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { showBulkDeletePopover && isSelecting && !selectedTxIDs.isEmpty },
            set: { presenting in
                if !presenting { showBulkDeletePopover = false }
            }
        )
    }

    var body: some View {
        NavigationStack {
            transactionsContent
                .navigationTitle("Transactions")
                .toolbar { toolbarItems }
                .searchable(text: $search, prompt: "Search transactions")
                .confirmationDialog(
                    "Delete \(selectedTxIDs.count) transactions?",
                    isPresented: isBulkDeleteDialogPresented,
                    titleVisibility: .visible
                ) {
                    bulkDeleteActions
                } message: {
                    Text("This action can't be undone.")
                }
                .navigationDestination(isPresented: $showImport) {
                    ImportTransactionsScreen(store: $store)
                }
                .navigationDestination(isPresented: $showRecurring) {
                    RecurringTransactionsView(store: $store)
                }
                .onChange(of: store.allCategories.count) { _ in
                    // Drop any selections that point at categories the user
                    // just deleted, so we don't filter against ghosts.
                    let valid = Set(store.allCategories)
                    filter.categories = filter.categories.intersection(valid)
                }
                .sheet(isPresented: $showAdd) {
                    TransactionSheet(
                        .add(initialMonth: store.selectedMonth),
                        in: $store,
                        source: .manual
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
                .fullScreenCover(item: editingWrapper) { wrapper in
                    TransactionSheet(
                        .edit(transactionID: wrapper.id),
                        in: $store,
                        source: .manual
                    )
                }
                .sheet(item: Binding(
                    get: { viewingAttachment },
                    set: { viewingAttachment = $0 }
                )) { transaction in
                    if let data = transaction.attachmentData, let type = transaction.attachmentType {
                        AttachmentViewer(attachmentData: data, attachmentType: type)
                    }
                }
                .sheet(item: Binding(
                    get: { inspectingTransaction },
                    set: { inspectingTransaction = $0 }
                )) { transaction in
                    TransactionInspectSheet(transaction: transaction, store: $store)
                }
                // COMMENTED OUT - recurring transactions باگ داره
                // .sheet(isPresented: $showRecurring) {
                //     AddRecurringSheet(store: $store)
                // }
                .sheet(isPresented: $showFilters) {
                    TransactionsFilterSheet(
                        filter: $filter,
                        categories: store.allCategories,
                        previewCount: { candidate in
                            let source = searchScope == .thisMonth
                                ? Analytics.monthTransactions(store: store)
                                : store.transactions
                            return candidate.apply(
                                to: source,
                                allCategories: store.allCategories
                            ).count
                        },
                        amountStats: {
                            let source = searchScope == .thisMonth
                                ? Analytics.monthTransactions(store: store)
                                : store.transactions
                            let amounts = source.map(\.amount).filter { $0 > 0 }
                            guard let lo = amounts.min(), let hi = amounts.max() else { return nil }
                            return (lo, hi)
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
        }
    }

    private var transactionsContent: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()
            transactionsListView
        }
    }

    @ViewBuilder
    private var bulkDeleteActions: some View {
        Button("Delete", role: .destructive) {
            let ids = selectedTxIDs
            let deletedTxs = store.transactions.filter { ids.contains($0.id) }
            pendingUndo = deletedTxs
            showBulkDeletePopover = false
            isSelecting = false
            selectedTxIDs.removeAll()

            withAnimation(uiAnim) {
                TransactionService.performDeleteBulk(deletedTxs, store: &store)
            }
            scheduleUndoCommit()
        }
        Button("Cancel", role: .cancel) {
            showBulkDeletePopover = false
        }
    }

    // MARK: - Active Filter Chips

    private struct ActiveFilterChip: Identifiable {
        let id: String
        let label: String
        let remove: () -> Void
    }

    private var activeFilterChips: [ActiveFilterChip] {
        var chips: [ActiveFilterChip] = []

        if filter.isDateActive {
            let cal = Calendar.current
            let sameDay = cal.isDate(filter.dateFrom, inSameDayAs: filter.dateTo)
            let f = DateFormatter()
            f.locale = .current
            f.setLocalizedDateFormatFromTemplate("MMM d")
            let label = sameDay
                ? f.string(from: filter.dateFrom)
                : "\(f.string(from: filter.dateFrom)) – \(f.string(from: filter.dateTo))"
            chips.append(.init(id: "date", label: label) {
                filter.useDateRange = false
            })
        }

        if filter.isCategoryActive(allCategories: store.allCategories) {
            let label = filter.categories.count == 1
                ? (filter.categories.first?.title ?? "Category")
                : "\(filter.categories.count) categories"
            chips.append(.init(id: "categories", label: label) {
                filter.categories = []
            })
        }

        if filter.isPaymentMethodActive {
            let label = filter.paymentMethods.count == 1
                ? (filter.paymentMethods.first?.displayName ?? "Method")
                : "\(filter.paymentMethods.count) methods"
            chips.append(.init(id: "paymentMethods", label: label) {
                filter.paymentMethods = []
            })
        }

        if filter.isAccountActive {
            let label: String
            if filter.accountIds.count == 1,
               let a = AccountManager.shared.accounts.first(where: { $0.id == filter.accountIds.first }) {
                label = a.name
            } else {
                label = "\(filter.accountIds.count) accounts"
            }
            chips.append(.init(id: "accounts", label: label) {
                filter.accountIds = []
            })
        }

        if filter.isAmountActive {
            let minC = DS.Format.cents(from: filter.minAmountText)
            let maxC = DS.Format.cents(from: filter.maxAmountText)
            let label: String
            switch (minC > 0, maxC > 0) {
            case (true, true):  label = "\(DS.Format.money(minC)) – \(DS.Format.money(maxC))"
            case (true, false): label = "≥ \(DS.Format.money(minC))"
            case (false, true): label = "≤ \(DS.Format.money(maxC))"
            default:            label = "Amount"
            }
            chips.append(.init(id: "amount", label: label) {
                filter.minAmountText = ""
                filter.maxAmountText = ""
            })
        }

        return chips
    }

    private var activeFilterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(activeFilterChips) { chip in
                    Button {
                        showFilters = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(chip.label)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.text)
                                .lineLimit(1)
                            Button {
                                withAnimation(uiAnim) { chip.remove() }
                                Haptics.selection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 13))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(chip.label) filter")
                        }
                        .padding(.leading, 11)
                        .padding(.trailing, 7)
                        .padding(.vertical, 6)
                        .background(
                            DS.Colors.accent.opacity(0.18),
                            in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(DS.Colors.accent.opacity(0.45), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if activeFilterChips.count > 1 {
                    Button {
                        withAnimation(uiAnim) { filter.reset() }
                        Haptics.success()
                    } label: {
                        Text("Clear all")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .animation(uiAnim, value: activeFilterChips.count)
    }

    // MARK: - Helper Views

    private var noBudgetBanner: some View {
        Button {
            goToBudget()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.warning)

                VStack(alignment: .leading, spacing: 2) {
                    Text("No budget set")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.text)
                    Text("Set a budget to unlock full insights")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.subtext)
                }

                Spacer()

                Text("Set up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(DS.Colors.accent.opacity(0.12), in: Capsule())
            }
            .padding(12)
            .background(DS.Colors.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Colors.warning.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var transactionsListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Budget nudge banner (non-blocking)
                if store.budgetTotal <= 0 {
                    noBudgetBanner
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                }

                // Active filter chips row
                if !activeFilterChips.isEmpty {
                    activeFilterChipsRow
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                }

                if filtered.isEmpty {
                    emptyStateView
                } else {
                    transactionsList
                }
            }
            .padding(.bottom, showUndoBar ? 80 : 24)
        }
        .background(DS.Colors.bg)
        .id("\(sortOrder.rawValue)-\(filtered.count)")
        .onAppear { recomputeFiltered() }
        .onChange(of: filteredChangeKey) { _, _ in recomputeFiltered() }
        .onChange(of: search) { oldValue, newValue in
            // Reset to This Month when search is cleared
            if newValue.isEmpty && searchScope == .allTime {
                searchScope = .thisMonth
            }
        }
        .alert(
            "Delete Transaction?",
            isPresented: isRowDeleteDialogPresented
        ) {
            deleteDialogButtons
        } message: {
            Text("This action cannot be undone")
        }
        .safeAreaInset(edge: .bottom) {
            if showUndoBar {
                undoBar
            }
        }
    }

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No transactions yet")
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
            Text("Tap + to get started")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var transactionsList: some View {
        Group {
            // Upcoming Payments Banner
            UpcomingPaymentsBanner(store: $store)
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // Search Scope Selector (if searching)
            if !search.isEmpty {
                HStack(spacing: 8) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                searchScope = scope
                            }
                            Haptics.selection()
                        } label: {
                            Text(scope.rawValue)
                                .font(.system(size: 13, weight: searchScope == scope ? .semibold : .medium))
                                .foregroundStyle(searchScope == scope ? .black : DS.Colors.text)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    searchScope == scope ?
                                    Color.white :
                                    DS.Colors.surface2,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text("\(filtered.count) \(filtered.count == 1 ? "result" : "results")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            // Transactions grouped by day
            if sortOrder == .dateNewest || sortOrder == .dateOldest {
                ForEach(Analytics.groupedByDay(filtered, ascending: sortOrder == .dateOldest), id: \.day) { group in
                    sectionHeader(group.title)
                    ForEach(group.items) { t in
                        transactionRowView(for: t)
                    }
                }
            } else if sortOrder == .categoryAZ {
                let grouped = Dictionary(grouping: filtered) { $0.category }
                let sortedKeys = grouped.keys.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

                ForEach(sortedKeys, id: \.self) { cat in
                    categorySectionHeader(cat)
                    ForEach(grouped[cat] ?? []) { t in
                        transactionRowView(for: t)
                    }
                }
            } else {
                let groups = groupConsecutiveByDay(filtered)

                ForEach(groups, id: \.id) { group in
                    sectionHeader(group.title)
                    ForEach(group.items) { t in
                        transactionRowView(for: t)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Colors.subtext)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }

    private func categorySectionHeader(_ cat: Category) -> some View {
        HStack(spacing: 6) {
            Image(systemName: cat.icon)
                .font(.system(size: 10))
                .foregroundStyle(cat.tint)
            Text(cat.title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 28)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func transactionRowView(for t: Transaction) -> some View {
        HStack(spacing: 10) {
            if isSelecting {
                selectionCheckmark(for: t)
            }

            TransactionRow(t: t)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleRowTap(for: t)
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
        .transition(.opacity.combined(with: .move(edge: .trailing)))
        .contextMenu {
            contextMenuButtons(for: t)
        } preview: {
            TransactionInspectPreview(transaction: t)
        }
    }

    @ViewBuilder
    private func selectionCheckmark(for t: Transaction) -> some View {
        let isSelected = selectedTxIDs.contains(t.id)
        Button {
            toggleSelection(for: t.id)
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? DS.Colors.positive : DS.Colors.subtext)
                .font(.system(size: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func contextMenuButtons(for t: Transaction) -> some View {
        Button {
            inspectingTransaction = t  // ← باز کردن صفحه کامل
        } label: {
            Label("Inspect", systemImage: "info.circle")
        }

        if t.attachmentData != nil, t.attachmentType != nil {
            Button {
                viewingAttachment = t
            } label: {
                Label("View Attachment", systemImage: "paperclip")
            }
        }

        Button {
            withAnimation(uiAnim) {
                editingTxID = t.id
            }
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Button(role: .destructive) {
            pendingDeleteID = t.id
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var deleteDialogButtons: some View {
        Button("Delete", role: .destructive) {
            let id = pendingDeleteID
            pendingDeleteID = nil

            guard let id,
                  let tx = store.transactions.first(where: { $0.id == id }) else { return }

            // Haptic reflects the deletion being saved, not full financial settlement.
            // Balance/goal reversals are deferred (async Task, may still be in flight).
            Haptics.transactionDeleted()
            AnalyticsManager.shared.track(.transactionDeleted)
            pendingUndo = [tx]
            withAnimation(uiAnim) {
                TransactionService.performDelete(tx, store: &store)
            }
            scheduleUndoCommit()
        }
        Button("Cancel", role: .cancel) {
            pendingDeleteID = nil
        }
    }

    private var undoBar: some View {
        HStack {
            Text("\(pendingUndo.count) transaction deleted")
                .foregroundStyle(DS.Colors.text)

            Spacer()

            Button("Undo") {
                undoDelete()
            }
            .foregroundStyle(DS.Colors.positive)
        }
        .padding()
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .scaleEffect(0.98)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helper Functions

    private func handleRowTap(for t: Transaction) {
        guard isSelecting else { return }
        toggleSelection(for: t.id)
    }

    private func toggleSelection(for id: UUID) {
        if selectedTxIDs.contains(id) {
            selectedTxIDs.remove(id)
        } else {
            selectedTxIDs.insert(id)
        }
        Haptics.selection()
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            leadingToolbar
        }
        ToolbarItem(placement: .topBarTrailing) {
            trailingToolbar
        }
    }

    @ViewBuilder
    private var leadingToolbar: some View {
        if isSelecting {
            HStack(spacing: 16) {  // ← افزایش spacing
                Button("Cancel") {
                    isSelecting = false
                    selectedTxIDs.removeAll()
                    showBulkDeletePopover = false
                }
                .foregroundStyle(DS.Colors.subtext)
                .frame(minWidth: 70)  // ← افزایش width
                .padding(.leading, 4)  // ← padding چپ

                Button {
                    guard !selectedTxIDs.isEmpty else { return }
                    showBulkDeletePopover = true
                } label: {
                    Text("Delete")
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Colors.danger)
                .disabled(selectedTxIDs.isEmpty)
                .frame(minWidth: 60)  // ← افزایش width
                .padding(.trailing, 4)  // ← padding راست
            }
        } else {
            Button("Select") {
                isSelecting = true
                Haptics.selection()
            }
            .foregroundStyle(DS.Colors.subtext)
        }
    }

    @ViewBuilder
    private var trailingToolbar: some View {
        if isSelecting {
            Button("Select All") {
                selectedTxIDs = Set(filtered.map { $0.id })
                Haptics.selection()
            }
            .foregroundStyle(DS.Colors.subtext)
            .lineLimit(1)
            .frame(minWidth: 85)  // ← افزایش width
            .padding(.trailing, 4)  // ← padding راست
        } else {
            TransactionsTrailingButtons(
                filtersActive: activeFilterCount > 0,
                showImport: $showImport,
                showFilters: $showFilters,
                showAdd: $showAdd,
                showRecurring: $showRecurring,  // ✅ ENABLED
                sortOrder: $sortOrder,  // ✅ Sort
                disabled: store.budgetTotal <= 0,
                uiAnim: uiAnim
            )
            .padding(.trailing, 6)
        }
    }

    // Helper binding for .sheet(item:) for edit transaction
    private var editingWrapper: Binding<UUIDWrapper?> {
        Binding<UUIDWrapper?>(
            get: { editingTxID.map { UUIDWrapper(id: $0) } },
            set: { editingTxID = $0?.id }
        )
    }
    // Add new state property for bulk delete popover
    @State private var showBulkDeletePopover = false
}

private struct TransactionsTrailingButtons: View {
    let filtersActive: Bool
    @Binding var showImport: Bool
    @Binding var showFilters: Bool
    @Binding var showAdd: Bool
    @Binding var showRecurring: Bool  // ✅ ENABLED
    @Binding var sortOrder: TransactionsView.TransactionSortOrder  // ✅ Sort
    let disabled: Bool
    let uiAnim: Animation

    @State private var showSortMenu = false
    @State private var showProAlert = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Recurring button - locked for free users
            Button {
                if MembershipManager.shared.isPro {
                    Haptics.light()
                    showRecurring = true
                } else {
                    showProAlert = true
                }
            } label: {
                ZStack {
                    Image(systemName: "repeat.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MembershipManager.shared.isPro ? DS.Colors.text : DS.Colors.subtext.opacity(0.5))
                        .frame(width: 36, height: 36, alignment: .center)

                    if !MembershipManager.shared.isPro {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DS.Colors.subtext)
                            .offset(x: 10, y: -10)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel("Recurring transactions")
            .alert("pro user access only", isPresented: $showProAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Recurring transactions are available for Pro users.")
            }

            Button { showImport = true } label: {
                Image(systemName: "arrow.down.circle")  // ← Circle version
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                    .frame(width: 36, height: 36, alignment: .center)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel("Import transactions")

            // Sort button with menu
            Menu {
                ForEach(TransactionsView.TransactionSortOrder.allCases, id: \.self) { order in
                    Button {
                        sortOrder = order
                        Haptics.selection()
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: sortOrder.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                    .frame(width: 36, height: 36, alignment: .center)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel("Sort transactions")

            Button { showFilters = true } label: {
                ZStack(alignment: .center) {
                    // Badge برای فیلتر فعال
                    if filtersActive {
                        Circle()
                            .fill(DS.Colors.positive)
                            .frame(width: 36, height: 36)
                    }

                    Image(systemName: filtersActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(filtersActive ? Color.black : DS.Colors.text)
                }
                .frame(width: 36, height: 36, alignment: .center)
                .animation(uiAnim, value: filtersActive)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel(filtersActive ? "Filters active" : "Filter transactions")

            Button { showAdd = true } label: {
                Image(systemName: "plus.circle")  // ← Circle version
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                    .frame(width: 36, height: 36, alignment: .center)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel("Add transaction")
        }
    }
}

private struct ImportTransactionsSheet: View {
    @Binding var store: Store

    var body: some View {
        ImportTransactionsScreen(store: $store)
    }
}

private struct TransactionsFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var filter: TransactionFilter
    let categories: [Category]
    let previewCount: (TransactionFilter) -> Int
    let amountStats: () -> (minCents: Int, maxCents: Int)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var accountManager: AccountManager = .shared
    @ObservedObject private var presetStore: SavedFilterPresetStore = .shared
    @State private var showSavePresetAlert = false
    @State private var pendingPresetName: String = ""

    private var hasAnyActiveFilter: Bool {
        filter.activeCount(allCategories: categories) > 0
    }

    private var availableAccounts: [Account] {
        accountManager.accounts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                if lhs.type.rawValue == rhs.type.rawValue {
                    return lhs.displayOrder < rhs.displayOrder
                }
                return AccountType.allCases.firstIndex(of: lhs.type) ?? 0
                    < AccountType.allCases.firstIndex(of: rhs.type) ?? 0
            }
    }

    private enum FilterSection: Hashable { case date, categories, payment, amount }
    @State private var expanded: Set<FilterSection> = []
    @State private var didInitExpansion = false
    @State private var categorySearch: String = ""

    // MARK: - Date presets

    private enum DatePreset: Hashable, CaseIterable {
        case all, today, thisWeek, thisMonth, last30Days, yearToDate, custom

        var label: String {
            switch self {
            case .all:        return "All time"
            case .today:      return "Today"
            case .thisWeek:   return "This week"
            case .thisMonth:  return "This month"
            case .last30Days: return "Last 30 days"
            case .yearToDate: return "Year to date"
            case .custom:     return "Custom"
            }
        }

        // Returns nil for `.all` and `.custom` (no canonical range to apply).
        func range(now: Date = Date()) -> (from: Date, to: Date)? {
            let cal = Calendar.current
            switch self {
            case .all, .custom:
                return nil
            case .today:
                let start = cal.startOfDay(for: now)
                return (start, now)
            case .thisWeek:
                let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
                let start = cal.date(from: comps) ?? cal.startOfDay(for: now)
                return (start, now)
            case .thisMonth:
                let start = cal.date(
                    from: cal.dateComponents([.year, .month], from: now)
                ) ?? cal.startOfDay(for: now)
                return (start, now)
            case .last30Days:
                let start = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now))
                    ?? cal.startOfDay(for: now)
                return (start, now)
            case .yearToDate:
                let start = cal.date(
                    from: cal.dateComponents([.year], from: now)
                ) ?? cal.startOfDay(for: now)
                return (start, now)
            }
        }
    }

    private var currentDatePreset: DatePreset {
        guard filter.useDateRange else { return .all }
        let cal = Calendar.current
        let from = cal.startOfDay(for: filter.dateFrom)
        let to = cal.startOfDay(for: filter.dateTo)
        for p in [DatePreset.today, .thisWeek, .thisMonth, .last30Days, .yearToDate] {
            if let r = p.range() {
                let rf = cal.startOfDay(for: r.from)
                let rt = cal.startOfDay(for: r.to)
                if rf == from && rt == to { return p }
            }
        }
        return .custom
    }

    // MARK: - Amount brackets

    private enum AmountBracket: Hashable, CaseIterable {
        case under10, ten50, fifty200, over200

        var minCents: Int? {
            switch self {
            case .under10:  return nil
            case .ten50:    return 1000
            case .fifty200: return 5000
            case .over200:  return 20000
            }
        }
        var maxCents: Int? {
            switch self {
            case .under10:  return 1000
            case .ten50:    return 5000
            case .fifty200: return 20000
            case .over200:  return nil
            }
        }
        var label: String {
            switch self {
            case .under10:  return "< \(DS.Format.money(1000))"
            case .ten50:    return "\(DS.Format.money(1000)) – \(DS.Format.money(5000))"
            case .fifty200: return "\(DS.Format.money(5000)) – \(DS.Format.money(20000))"
            case .over200:  return "\(DS.Format.money(20000))+"
            }
        }
    }

    private var activeAmountBracket: AmountBracket? {
        let cur = (
            min: DS.Format.cents(from: filter.minAmountText),
            max: DS.Format.cents(from: filter.maxAmountText)
        )
        for b in AmountBracket.allCases {
            let bMin = b.minCents ?? 0
            let bMax = b.maxCents ?? 0
            if cur.min == bMin && cur.max == bMax { return b }
        }
        return nil
    }

    private func apply(_ bracket: AmountBracket) {
        withAnimation(uiAnim) {
            // Toggle off if already selected.
            if activeAmountBracket == bracket {
                filter.minAmountText = ""
                filter.maxAmountText = ""
            } else {
                filter.minAmountText = bracket.minCents.map { String($0 / 100) } ?? ""
                filter.maxAmountText = bracket.maxCents.map { String($0 / 100) } ?? ""
            }
        }
        Haptics.selection()
    }

    private func apply(_ preset: DatePreset) {
        withAnimation(uiAnim) {
            switch preset {
            case .all:
                filter.useDateRange = false
            case .custom:
                // Switch into custom mode without overwriting the user's
                // last picked dates.
                filter.useDateRange = true
            default:
                if let r = preset.range() {
                    filter.useDateRange = true
                    filter.dateFrom = r.from
                    filter.dateTo = r.to
                }
            }
        }
        Haptics.selection()
    }

    private var filteredCategories: [Category] {
        let q = categorySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return categories }
        return categories.filter { $0.title.lowercased().contains(q) }
    }

    private var allSelected: Bool {
        filter.categories.isEmpty || filter.categories.count == categories.count
    }
    private var allPaymentMethodsSelected: Bool {
        filter.paymentMethods.isEmpty
            || filter.paymentMethods.count == PaymentMethod.allCases.count
    }
    private var uiAnim: Animation {
        reduceMotion
            ? .linear(duration: 0.001)
            : .spring(response: 0.35, dampingFraction: 0.9, blendDuration: 0.0)
    }

    private static let summaryDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    private func summary(for section: FilterSection) -> String {
        switch section {
        case .date:
            let preset = currentDatePreset
            if preset == .custom {
                let f = Self.summaryDateFormatter
                return "\(f.string(from: filter.dateFrom)) – \(f.string(from: filter.dateTo))"
            }
            return preset.label
        case .categories:
            if allSelected { return "All" }
            return "\(filter.categories.count) of \(categories.count)"
        case .payment:
            let pm = filter.isPaymentMethodActive
            let acc = filter.isAccountActive
            switch (pm, acc) {
            case (false, false):
                return "All"
            case (true, false):
                return filter.paymentMethods.count == 1
                    ? (filter.paymentMethods.first?.displayName ?? "1")
                    : "\(filter.paymentMethods.count) methods"
            case (false, true):
                return "\(filter.accountIds.count) account\(filter.accountIds.count == 1 ? "" : "s")"
            case (true, true):
                return "\(filter.paymentMethods.count + filter.accountIds.count) selected"
            }
        case .amount:
            let hasMin = !filter.minAmountText.trimmingCharacters(in: .whitespaces).isEmpty
            let hasMax = !filter.maxAmountText.trimmingCharacters(in: .whitespaces).isEmpty
            switch (hasMin, hasMax) {
            case (true, true):  return "\(filter.minAmountText) – \(filter.maxAmountText)"
            case (true, false): return "≥ \(filter.minAmountText)"
            case (false, true): return "≤ \(filter.maxAmountText)"
            default:            return "Any amount"
            }
        }
    }

    private func isActive(_ section: FilterSection) -> Bool {
        switch section {
        case .date:       return filter.isDateActive
        case .categories: return filter.isCategoryActive(allCategories: categories)
        case .payment:    return filter.isPaymentMethodActive || filter.isAccountActive
        case .amount:     return filter.isAmountActive
        }
    }

    private func toggle(_ section: FilterSection) {
        withAnimation(uiAnim) {
            if expanded.contains(section) {
                expanded.remove(section)
            } else {
                expanded.insert(section)
            }
        }
        Haptics.selection()
    }

    private func sectionHeader(_ section: FilterSection, title: String) -> some View {
        let isOpen = expanded.contains(section)
        let active = isActive(section)
        let summaryText = summary(for: section)
        return Button { toggle(section) } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                Text(summaryText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(active ? DS.Colors.accent : DS.Colors.subtext)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.subtext)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(uiAnim, value: isOpen)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(summaryText)")
        .accessibilityHint(isOpen ? "Tap to collapse" : "Tap to expand")
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }

    private func ensureInitialExpansion() {
        guard !didInitExpansion else { return }
        didInitExpansion = true
        var seed: Set<FilterSection> = []
        for s in [FilterSection.date, .categories, .payment, .amount] where isActive(s) {
            seed.insert(s)
        }
        // If nothing is active yet, open Date by default so the sheet doesn't
        // look empty on first launch.
        if seed.isEmpty { seed = [.date] }
        expanded = seed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if !presetStore.presets.isEmpty || hasAnyActiveFilter {
                            savedPresetsRow
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(.date, title: "Date Range")

                                if expanded.contains(.date) {
                                    let active = currentDatePreset
                                    HFlow(spacing: 8) {
                                        ForEach(DatePreset.allCases, id: \.self) { p in
                                            let isOn = (p == active)
                                            Button { apply(p) } label: {
                                                Text(p.label)
                                                    .font(DS.Typography.caption)
                                                    .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                                    .padding(.horizontal, 11)
                                                    .padding(.vertical, 7)
                                                    .background(
                                                        (isOn ? DS.Colors.accent.opacity(0.20) : DS.Colors.surface2),
                                                        in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                    )
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                            .strokeBorder(isOn ? DS.Colors.accent.opacity(0.55) : Color.clear, lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .animation(uiAnim, value: active)

                                    if active == .custom {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("From")
                                                    .font(DS.Typography.caption)
                                                    .foregroundStyle(DS.Colors.subtext)
                                                DatePicker("", selection: $filter.dateFrom, displayedComponents: [.date])
                                                    .labelsHidden()
                                            }
                                            Spacer()
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text("To")
                                                    .font(DS.Typography.caption)
                                                    .foregroundStyle(DS.Colors.subtext)
                                                DatePicker("", selection: $filter.dateTo, displayedComponents: [.date])
                                                    .labelsHidden()
                                            }
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(.categories, title: "Categories")

                                if expanded.contains(.categories) {
                                HStack(spacing: 8) {
                                    if categories.count > 12 {
                                        HStack(spacing: 6) {
                                            Image(systemName: "magnifyingglass")
                                                .font(.system(size: 12))
                                                .foregroundStyle(DS.Colors.subtext)
                                            TextField("Search categories", text: $categorySearch)
                                                .font(DS.Typography.caption)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled(true)
                                            if !categorySearch.isEmpty {
                                                Button {
                                                    categorySearch = ""
                                                } label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(.system(size: 13))
                                                        .foregroundStyle(DS.Colors.subtext)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    Spacer(minLength: 0)
                                    Button(allSelected ? "Clear" : "All") {
                                        withAnimation(uiAnim) {
                                            if allSelected {
                                                filter.categories = []
                                            } else {
                                                filter.categories = Set(categories)
                                            }
                                        }
                                    }
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                    .buttonStyle(.plain)
                                }

                                HFlow(spacing: 8) {
                                    ForEach(filteredCategories, id: \.self) { c in
                                        let isOn = filter.categories.isEmpty || filter.categories.contains(c)
                                        Button {
                                            withAnimation(uiAnim) {
                                                // If filter is currently "all" (empty),
                                                // materialise it before removing one.
                                                var current = filter.categories.isEmpty
                                                    ? Set(categories)
                                                    : filter.categories
                                                if isOn {
                                                    current.remove(c)
                                                } else {
                                                    current.insert(c)
                                                }
                                                filter.categories = current
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: c.icon)
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(c.title)
                                            }
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(
                                                (isOn ? c.tint.opacity(0.22) : DS.Colors.surface2),
                                                in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                    .strokeBorder(isOn ? c.tint.opacity(0.55) : Color.clear, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .animation(uiAnim, value: filter.categories)
                                .animation(uiAnim, value: filteredCategories.count)

                                if filteredCategories.isEmpty && !categorySearch.isEmpty {
                                    Text("No categories match \"\(categorySearch)\"")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                        .padding(.top, 4)
                                } else if !filter.categories.isEmpty && filter.categories.count != categories.count {
                                    Text("\(filter.categories.count) of \(categories.count) selected")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                } // end if expanded .categories
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(.payment, title: "Account")

                                if expanded.contains(.payment) {

                                // Quick Cash / Card pills (PaymentMethod axis)
                                Text("Quick")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .textCase(.uppercase)

                                HFlow(spacing: 8) {
                                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                                        let isOn = filter.paymentMethods.contains(method)
                                        Button {
                                            withAnimation(uiAnim) {
                                                if isOn {
                                                    filter.paymentMethods.remove(method)
                                                } else {
                                                    filter.paymentMethods.insert(method)
                                                }
                                            }
                                            Haptics.selection()
                                        } label: {
                                            HStack(spacing: 6) {
                                                Image(systemName: method.icon)
                                                    .font(.system(size: 11, weight: .semibold))
                                                Text(method.displayName)
                                            }
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 7)
                                            .background(
                                                (isOn ? method.accentColor.opacity(0.20) : DS.Colors.surface2),
                                                in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                    .strokeBorder(isOn ? method.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .animation(uiAnim, value: filter.paymentMethods)

                                // Real-account chips, grouped by account type
                                if !availableAccounts.isEmpty {
                                    Text("Accounts")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(DS.Colors.subtext)
                                        .textCase(.uppercase)
                                        .padding(.top, 6)

                                    let groups: [AccountType] = AccountType.allCases.filter { type in
                                        availableAccounts.contains { $0.type == type }
                                    }
                                    ForEach(groups, id: \.self) { type in
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(type.displayName)
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)

                                            HFlow(spacing: 8) {
                                                ForEach(availableAccounts.filter { $0.type == type }) { acc in
                                                    let isOn = filter.accountIds.contains(acc.id)
                                                    Button {
                                                        withAnimation(uiAnim) {
                                                            if isOn {
                                                                filter.accountIds.remove(acc.id)
                                                            } else {
                                                                filter.accountIds.insert(acc.id)
                                                            }
                                                        }
                                                        Haptics.selection()
                                                    } label: {
                                                        HStack(spacing: 6) {
                                                            Image(systemName: type.iconName)
                                                                .font(.system(size: 11, weight: .semibold))
                                                            Text(acc.name)
                                                        }
                                                        .font(DS.Typography.caption)
                                                        .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                                        .padding(.horizontal, 11)
                                                        .padding(.vertical, 7)
                                                        .background(
                                                            (isOn ? DS.Colors.accent.opacity(0.20) : DS.Colors.surface2),
                                                            in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                        )
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                                .strokeBorder(isOn ? DS.Colors.accent.opacity(0.55) : Color.clear, lineWidth: 1)
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                    }
                                    .animation(uiAnim, value: filter.accountIds)

                                    if filter.isAccountActive || filter.isPaymentMethodActive {
                                        Button {
                                            withAnimation(uiAnim) {
                                                filter.paymentMethods = []
                                                filter.accountIds = []
                                            }
                                            Haptics.selection()
                                        } label: {
                                            Text("Clear selection")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 4)
                                    }
                                }
                                } // end if expanded .payment
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(.amount, title: "Amount Range")

                                if expanded.contains(.amount) {
                                if let stats = amountStats() {
                                    Text("Range in your data: \(DS.Format.money(stats.minCents)) – \(DS.Format.money(stats.maxCents))")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }

                                HFlow(spacing: 8) {
                                    ForEach(AmountBracket.allCases, id: \.self) { b in
                                        let isOn = (activeAmountBracket == b)
                                        Button { apply(b) } label: {
                                            Text(b.label)
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                                .padding(.horizontal, 11)
                                                .padding(.vertical, 7)
                                                .background(
                                                    (isOn ? DS.Colors.accent.opacity(0.20) : DS.Colors.surface2),
                                                    in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                )
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                        .strokeBorder(isOn ? DS.Colors.accent.opacity(0.55) : Color.clear, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .animation(uiAnim, value: activeAmountBracket)

                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Min")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        TextField("0.00", text: $filter.minAmountText)
                                            .keyboardType(.decimalPad)
                                            .font(DS.Typography.number)
                                            .padding(10)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Max")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        TextField("0.00", text: $filter.maxAmountText)
                                            .keyboardType(.decimalPad)
                                            .font(DS.Typography.number)
                                            .padding(10)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                                } // end if expanded .amount
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { stickyFooter }
            .onAppear { ensureInitialExpansion() }
            .alert("Save filter", isPresented: $showSavePresetAlert) {
                TextField("Name", text: $pendingPresetName)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    presetStore.add(name: pendingPresetName, filter: filter)
                    pendingPresetName = ""
                }
                .disabled(pendingPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Cancel", role: .cancel) {
                    pendingPresetName = ""
                }
            } message: {
                Text("Pin this combination of filters so you can re-apply it in one tap.")
            }
        }
    }

    private var savedPresetsRow: some View {
        let active = presetStore.matches(filter)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presetStore.presets) { preset in
                    let isOn = (active?.id == preset.id)
                    Button {
                        withAnimation(uiAnim) { filter = preset.filter }
                        Haptics.selection()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(preset.name)
                                .font(DS.Typography.caption)
                                .lineLimit(1)
                            Button {
                                withAnimation(uiAnim) { presetStore.remove(preset.id) }
                                Haptics.selection()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete preset \(preset.name)")
                        }
                        .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                        .padding(.leading, 11)
                        .padding(.trailing, 6)
                        .padding(.vertical, 7)
                        .background(
                            (isOn ? DS.Colors.accent.opacity(0.22) : DS.Colors.surface2),
                            in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(isOn ? DS.Colors.accent.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if hasAnyActiveFilter && active == nil && presetStore.canAddMore {
                    Button {
                        pendingPresetName = ""
                        showSavePresetAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Save current")
                                .font(DS.Typography.caption)
                        }
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            DS.Colors.accent.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(DS.Colors.accent.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -16)
    }

    private var stickyFooter: some View {
        let count = previewCount(filter)
        let hasActive = filter.activeCount(allCategories: categories) > 0
        return HStack(spacing: 12) {
            if hasActive {
                Button {
                    withAnimation(uiAnim) { filter.reset() }
                    Haptics.success()
                } label: {
                    Text("Reset")
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer(minLength: 0)

            Button {
                Haptics.success()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(count == 0 ? "No matches" : "Show \(count) \(count == 1 ? "transaction" : "transactions")")
                }
            }
            .buttonStyle(DS.PrimaryButton())
            .disabled(count == 0)
            .opacity(count == 0 ? 0.55 : 1)
            .animation(uiAnim, value: count)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            DS.Colors.bg
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Colors.subtext.opacity(0.15))
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(uiAnim, value: filter.activeCount(allCategories: categories) > 0)
    }
}
