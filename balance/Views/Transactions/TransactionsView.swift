import SwiftUI

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
    @State private var selectedCategories: Set<Category> = []
    @State private var selectedPaymentMethods: Set<PaymentMethod> = Set(PaymentMethod.allCases)  // ← همه انتخاب شده
    @State private var useDateRange = false
    @State private var dateFrom = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var dateTo = Date()
    @State private var minAmountText = ""
    @State private var maxAmountText = ""
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

    private var filtered: [Transaction] {
        // Choose source based on search scope
        let sourceTx = searchScope == .thisMonth
            ? Analytics.monthTransactions(store: store)
            : store.transactions

        // Text search
        var out = sourceTx
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let s = trimmed.lowercased()
            out = out.filter { $0.note.lowercased().contains(s) || $0.category.title.lowercased().contains(s) }
        }

        // Category filter — only apply when user has actively chosen a subset.
        // Empty set means "no filter active" (show all), not "show nothing".
        if !selectedCategories.isEmpty && selectedCategories.count != store.allCategories.count {
            out = out.filter { selectedCategories.contains($0.category) }
        }

        // Payment method filter - فقط اگه همه انتخاب نشده باشن
        if !selectedPaymentMethods.isEmpty && selectedPaymentMethods.count != PaymentMethod.allCases.count {
            out = out.filter { selectedPaymentMethods.contains($0.paymentMethod) }
        }

        // Amount range filter (values are stored in euro cents)
        let minCents = DS.Format.cents(from: minAmountText)
        let maxCents = DS.Format.cents(from: maxAmountText)
        if minCents > 0 {
            out = out.filter { $0.amount >= minCents }
        }
        if maxCents > 0 {
            out = out.filter { $0.amount <= maxCents }
        }

        // Date range filter
        if useDateRange {
            let cal = Calendar.current
            let start = cal.startOfDay(for: dateFrom)
            // Include the entire end day
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dateTo)) ?? dateTo
            out = out.filter { $0.date >= start && $0.date < end }
        }

        // Apply sort order - ultra simple
        let result: [Transaction]
        switch sortOrder {
        case .dateNewest:
            result = out.sorted(by: { $0.date > $1.date })
        case .dateOldest:
            result = out.sorted(by: { $0.date < $1.date })
        case .amountHighest:
            result = out.sorted(by: { $0.amount > $1.amount })
        case .amountLowest:
            result = out.sorted(by: { $0.amount < $1.amount })
        case .categoryAZ:
            result = out.sorted(by: { $0.category.title.localizedStandardCompare($1.category.title) == .orderedAscending })
        }

        return result
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
        var n = 0
        if selectedCategories.count != store.allCategories.count { n += 1 }
        if !selectedPaymentMethods.isEmpty && selectedPaymentMethods.count != PaymentMethod.allCases.count { n += 1 }  // ← درست شد
        if useDateRange { n += 1 }
        if DS.Format.cents(from: minAmountText) > 0 || DS.Format.cents(from: maxAmountText) > 0 { n += 1 }
        return n
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
                .onAppear {
                    // Default: select all (including custom categories)
                    if selectedCategories.isEmpty {
                        selectedCategories = Set(store.allCategories)
                    }
                }
                .onChange(of: store.allCategories.count) { _ in
                    // Update selectedCategories when new categories are added
                    selectedCategories = Set(store.allCategories)
                }
                .sheet(isPresented: $showAdd) {
                    AddTransactionSheet(store: $store, initialMonth: store.selectedMonth)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
                .fullScreenCover(item: editingWrapper) { wrapper in
                    EditTransactionSheet(store: $store, transactionID: wrapper.id)
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
                        selectedCategories: $selectedCategories,
                        categories: store.allCategories,
                        useDateRange: $useDateRange,
                        dateFrom: $dateFrom,
                        dateTo: $dateTo,
                        minAmountText: $minAmountText,
                        maxAmountText: $maxAmountText,
                        selectedPaymentMethods: $selectedPaymentMethods
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
        Image(systemName: selectedTxIDs.contains(t.id) ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selectedTxIDs.contains(t.id) ? DS.Colors.positive : DS.Colors.subtext)
            .font(.system(size: 18))
            .onTapGesture {
                toggleSelection(for: t.id)
            }
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
                if SubscriptionManager.shared.isPro {
                    Haptics.light()
                    showRecurring = true
                } else {
                    showProAlert = true
                }
            } label: {
                ZStack {
                    Image(systemName: "repeat.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SubscriptionManager.shared.isPro ? DS.Colors.text : DS.Colors.subtext.opacity(0.5))
                        .frame(width: 36, height: 36, alignment: .center)

                    if !SubscriptionManager.shared.isPro {
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

    @Binding var selectedCategories: Set<Category>
    let categories: [Category]
    @Binding var useDateRange: Bool
    @Binding var dateFrom: Date
    @Binding var dateTo: Date
    @Binding var minAmountText: String
    @Binding var maxAmountText: String
    @Binding var selectedPaymentMethods: Set<PaymentMethod>  // ← جدید

    private var allSelected: Bool { selectedCategories.count == categories.count }
    private var allPaymentMethodsSelected: Bool { selectedPaymentMethods.count == PaymentMethod.allCases.count }  // ← جدید
    private let uiAnim = Animation.spring(response: 0.35, dampingFraction: 0.9, blendDuration: 0.0)

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Categories")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Button(allSelected ? "Clear" : "All") {
                                        withAnimation(uiAnim) {
                                            if allSelected {
                                                selectedCategories = []
                                            } else {
                                                selectedCategories = Set(categories)
                                            }
                                        }
                                    }
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                    .buttonStyle(.plain)
                                }

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(categories, id: \.self) { c in
                                            let isOn = selectedCategories.contains(c)
                                            Button {
                                                withAnimation(uiAnim) {
                                                    if isOn {
                                                        selectedCategories.remove(c)
                                                    } else {
                                                        selectedCategories.insert(c)
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 8) {
                                                    Image(systemName: c.icon)
                                                    Text(c.title)
                                                }
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 9)
                                                .background(
                                                    (isOn ? c.tint.opacity(0.18) : DS.Colors.surface2),
                                                    in: RoundedRectangle(cornerRadius: 999, style: .continuous)
                                                )
                                                .animation(uiAnim, value: selectedCategories)
                                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }

                                if selectedCategories.isEmpty {
                                    Text("Select at least one category")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Payment Methods")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Button {
                                        Haptics.selection()
                                        withAnimation(uiAnim) {
                                            if allPaymentMethodsSelected {
                                                selectedPaymentMethods = []
                                            } else {
                                                selectedPaymentMethods = Set(PaymentMethod.allCases)
                                            }
                                        }
                                    } label: {
                                        Text(allPaymentMethodsSelected ? "Clear" : "All")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                    .buttonStyle(.plain)
                                }

                                HStack(spacing: 12) {
                                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                                        let isOn = selectedPaymentMethods.contains(method)
                                        Button {
                                            withAnimation(uiAnim) {
                                                if isOn {
                                                    selectedPaymentMethods.remove(method)
                                                } else {
                                                    selectedPaymentMethods.insert(method)
                                                }
                                                Haptics.selection()
                                            }
                                        } label: {
                                            HStack(spacing: 8) {
                                                ZStack {
                                                    if isOn {
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .fill(
                                                                LinearGradient(
                                                                    colors: method.gradientColors,
                                                                    startPoint: .topLeading,
                                                                    endPoint: .bottomTrailing
                                                                )
                                                            )
                                                            .frame(width: 32, height: 32)
                                                    } else {
                                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                            .fill(method.accentColor.opacity(0.12))
                                                            .frame(width: 32, height: 32)
                                                    }

                                                    Image(systemName: method.icon)
                                                        .font(.system(size: 16, weight: .semibold))
                                                        .foregroundStyle(isOn ? .white : method.accentColor)
                                                }

                                                Text(method.displayName)
                                                    .font(DS.Typography.body.weight(isOn ? .semibold : .regular))
                                            }
                                            .foregroundStyle(isOn ? DS.Colors.text : DS.Colors.subtext)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                isOn ? DS.Colors.surface2 : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            )
                                            .shadow(color: isOn ? method.accentColor.opacity(0.15) : .black.opacity(0.03), radius: 6, x: 0, y: 2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                if selectedPaymentMethods.isEmpty {
                                    Text("Select at least one payment method")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Date Range")
                                        .font(DS.Typography.section)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Toggle("", isOn: $useDateRange)
                                        .onChange(of: useDateRange) { _, _ in
                                            withAnimation(uiAnim) { }
                                        }
                                        .labelsHidden()
                                        .toggleStyle(SwitchToggleStyle(tint: DS.Colors.accent))
                                        .animation(uiAnim, value: useDateRange)
                                }
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(useDateRange ? Color.clear : DS.Colors.surface2.opacity(0.6))
                                )

                                if useDateRange {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("From")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)
                                            DatePicker("", selection: $dateFrom, displayedComponents: [.date])
                                                .labelsHidden()
                                        }
                                        Spacer()
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text("To")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)
                                            DatePicker("", selection: $dateTo, displayedComponents: [.date])
                                                .labelsHidden()
                                        }
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                } else {
                                    Text("Date range filtering is off")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                        .transition(.opacity)
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Amount Range")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Min")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        TextField("0.00", text: $minAmountText)
                                            .keyboardType(.decimalPad)
                                            .font(DS.Typography.number)
                                            .padding(10)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Max")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        TextField("0.00", text: $maxAmountText)
                                            .keyboardType(.decimalPad)
                                            .font(DS.Typography.number)
                                            .padding(10)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }

                                Text("Example: 0 - 100")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }

                        HStack(spacing: 12) {
                            Button {
                                withAnimation(uiAnim) {
                                    selectedCategories = Set(categories)
                                    selectedPaymentMethods = Set(PaymentMethod.allCases)  // ← فیکس
                                    useDateRange = false
                                    dateFrom = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
                                    dateTo = Date()
                                    minAmountText = ""
                                    maxAmountText = ""
                                }
                                Haptics.success()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset")
                                }
                            }
                            .buttonStyle(DS.PrimaryButton())

                            Button {
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Apply")
                                }
                            }
                            .buttonStyle(DS.PrimaryButton())
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }
}
