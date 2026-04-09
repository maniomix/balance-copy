// ==========================================
// Recurring Transactions
// ==========================================

import SwiftUI
import Combine

// MARK: - Recurring Transaction Model

struct RecurringTransaction: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var amount: Int  // cents
    var category: Category
    var frequency: RecurringFrequency
    var startDate: Date
    var endDate: Date?
    var isActive: Bool
    var lastProcessedDate: Date?
    var paymentMethod: PaymentMethod
    var note: String
    
    init(
        id: UUID = UUID(),
        name: String,
        amount: Int,
        category: Category,
        frequency: RecurringFrequency,
        startDate: Date,
        endDate: Date? = nil,
        isActive: Bool = true,
        lastProcessedDate: Date? = nil,
        paymentMethod: PaymentMethod = .card,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.category = category
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.lastProcessedDate = lastProcessedDate
        self.paymentMethod = paymentMethod
        self.note = note
    }
    
    func nextOccurrence(from date: Date = Date()) -> Date? {
        guard isActive else { return nil }
        
        let calendar = Calendar.current
        let lastProcessed = lastProcessedDate ?? calendar.date(byAdding: .day, value: -1, to: startDate)!
        
        var nextDate: Date?
        
        switch frequency {
        case .daily:
            nextDate = calendar.date(byAdding: .day, value: 1, to: lastProcessed)
        case .weekly:
            nextDate = calendar.date(byAdding: .weekOfYear, value: 1, to: lastProcessed)
        case .monthly:
            nextDate = calendar.date(byAdding: .month, value: 1, to: lastProcessed)
        case .yearly:
            nextDate = calendar.date(byAdding: .year, value: 1, to: lastProcessed)
        }
        
        if let endDate = endDate, let next = nextDate, next > endDate {
            return nil
        }
        
        return nextDate
    }
}

// MARK: - Recurring Transactions View

struct RecurringTransactionsView: View {
    @Binding var store: Store
    @State private var showAddSheet = false
    
    var activeRecurring: [RecurringTransaction] {
        store.recurringTransactions.filter { $0.isActive }
    }
    
    var inactiveRecurring: [RecurringTransaction] {
        store.recurringTransactions.filter { !$0.isActive }
    }
    
    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    statsCard

                    if !activeRecurring.isEmpty {
                        sectionView(title: "Active", items: activeRecurring)
                    }

                    if !inactiveRecurring.isEmpty {
                        sectionView(title: "Paused", items: inactiveRecurring, dimmed: true)
                    }

                    if store.recurringTransactions.isEmpty {
                        emptyState
                    }
                }
                .padding(.vertical)
            }
        }
        .navigationTitle("Recurring")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddSheet = true
                    Haptics.medium()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Colors.text)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddRecurringSheet(store: $store)
        }
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        DS.Card {
            HStack(spacing: 0) {
                // Monthly total
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly Total")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    
                    let monthlyTotal = activeRecurring
                        .filter { $0.frequency == .monthly }
                        .reduce(0) { $0 + $1.amount }
                    
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(monthlyTotal))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                }
                
                Spacer()
                
                // Counters
                HStack(spacing: 16) {
                    StatPill(count: activeRecurring.count, label: "Active", color: DS.Colors.positive)
                    StatPill(count: inactiveRecurring.count, label: "Paused", color: DS.Colors.warning)
                }
            }
        }
        .padding(.horizontal)
    }
    
    // MARK: - Section
    
    private func sectionView(title: String, items: [RecurringTransaction], dimmed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DS.Typography.section)
                .foregroundStyle(dimmed ? DS.Colors.subtext : DS.Colors.text)
                .padding(.horizontal)
            
            ForEach(items) { recurring in
                RecurringRow(
                    recurring: recurring,
                    onToggle: { toggleActive(recurring) },
                    onDelete: { deleteRecurring(recurring) }
                )
                .opacity(dimmed ? 0.6 : 1)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 48))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
            
            Text("No Recurring Transactions")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)
            
            Text("Automate your regular expenses")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
            
            Button {
                showAddSheet = true
                Haptics.medium()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Recurring")
                }
            }
            .buttonStyle(DS.PrimaryButton())
            .padding(.horizontal, 40)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Actions
    
    private func toggleActive(_ recurring: RecurringTransaction) {
        if let index = store.recurringTransactions.firstIndex(where: { $0.id == recurring.id }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                store.recurringTransactions[index].isActive.toggle()
            }
            Haptics.medium()
        }
    }
    
    private func deleteRecurring(_ recurring: RecurringTransaction) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            store.recurringTransactions.removeAll { $0.id == recurring.id }
        }
        Haptics.success()
    }
}

// MARK: - Recurring Row

struct RecurringRow: View {
    let recurring: RecurringTransaction
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    @State private var showDeleteAlert = false
    
    var body: some View {
        DS.Card {
            HStack(spacing: 14) {
                // Category icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(recurring.category.tint.opacity(0.12))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: recurring.category.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(recurring.category.tint)
                }
                
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(recurring.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    
                    HStack(spacing: 6) {
                        Text(recurring.frequency.displayName)
                            .font(.system(size: 12, weight: .medium))
                        
                        if let next = recurring.nextOccurrence() {
                            Text("·")
                            Text(formatDate(next))
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(DS.Colors.subtext)
                }
                
                Spacer()
                
                // Amount + actions
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(recurring.amount))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    
                    HStack(spacing: 8) {
                        Button {
                            onToggle()
                        } label: {
                            Image(systemName: recurring.isActive ? "pause.fill" : "play.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(recurring.isActive ? DS.Colors.warning : DS.Colors.positive)
                                .frame(width: 28, height: 28)
                                .background(
                                    (recurring.isActive ? DS.Colors.warning : DS.Colors.positive).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                        
                        Button {
                            showDeleteAlert = true
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.danger)
                                .frame(width: 28, height: 28)
                                .background(
                                    DS.Colors.danger.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .alert("Delete Recurring?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This will remove '\(recurring.name)' permanently.")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Stat Pill

struct StatPill: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DS.Colors.surface2, in: Capsule())
    }
}

// MARK: - Stat Item (kept for compatibility)

struct StatItem: View {
    let count: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.subtext)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Liquid Glass Card (kept for compatibility)

struct LiquidGlassCard<Content: View>: View {
    let content: () -> Content
    
    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }
    
    var body: some View {
        content()
            .padding(16)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Add Recurring Sheet

struct AddRecurringSheet: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var amount = ""
    @State private var selectedCategory: Category = .groceries
    @State private var frequency: RecurringFrequency = .monthly
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var paymentMethod: PaymentMethod = .card
    @State private var note = ""
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (Double(amount) ?? 0) > 0
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Name
                        fieldSection("Name") {
                            TextField("e.g., Netflix", text: $name)
                                .textFieldStyle(DS.TextFieldStyle())
                        }
                        
                        // Amount
                        fieldSection("Amount") {
                            TextField("0.00", text: $amount)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(DS.TextFieldStyle())
                        }
                        
                        // Category — same height as text fields
                        fieldSection("Category") {
                            Menu {
                                ForEach(store.allCategories, id: \.self) { category in
                                    Button {
                                        selectedCategory = category
                                    } label: {
                                        Label(category.title, systemImage: category.icon)
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedCategory.icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(selectedCategory.tint)
                                    
                                    Text(selectedCategory.title)
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(12)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                        
                        // Frequency
                        fieldSection("Frequency") {
                            FrequencyPicker(selected: $frequency)
                        }
                        
                        // Dates — grouped together
                        VStack(spacing: 14) {
                            fieldSection("Start Date") {
                                HStack {
                                    Text(formatDateDisplay(startDate))
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                    
                                    Spacer()
                                    
                                    DatePicker("", selection: $startDate, displayedComponents: .date)
                                        .labelsHidden()
                                        .scaleEffect(0.9)
                                }
                                .padding(12)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            
                            // End date toggle + picker inline
                            HStack {
                                Text("End Date")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DS.Colors.subtext)
                                
                                Spacer()
                                
                                Toggle("", isOn: $hasEndDate.animation(.spring(response: 0.3)))
                                    .labelsHidden()
                                    .tint(DS.Colors.accent)
                            }
                            
                            if hasEndDate {
                                HStack {
                                    Text(formatDateDisplay(endDate))
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                    
                                    Spacer()
                                    
                                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                        .labelsHidden()
                                        .scaleEffect(0.9)
                                }
                                .padding(12)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        
                        // Save
                        Button {
                            saveRecurring()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Create Recurring")
                            }
                        }
                        .buttonStyle(DS.PrimaryButton())
                        .disabled(!isValid)
                        .opacity(isValid ? 1 : 0.5)
                        .padding(.top, 8)
                    }
                    .padding()
                }
            }
            .navigationTitle("New Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }
    
    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            
            content()
        }
    }
    
    private func saveRecurring() {
        let amountDouble = Double(amount) ?? 0
        let amountCents = Int(amountDouble * 100)
        guard amountCents > 0 else { return }
        
        let recurring = RecurringTransaction(
            name: name.trimmingCharacters(in: .whitespaces),
            amount: amountCents,
            category: selectedCategory,
            frequency: frequency,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil,
            paymentMethod: paymentMethod,
            note: note
        )
        
        store.recurringTransactions.append(recurring)
        Haptics.success()
        dismiss()
    }
    
    private func formatDateDisplay(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }
}

// MARK: - Glass TextField Style (compatibility)

struct GlassTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(DS.Typography.body)
            .padding(12)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Frequency Picker

struct FrequencyPicker: View {
    @Binding var selected: RecurringFrequency
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(RecurringFrequency.allCases, id: \.self) { freq in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selected = freq
                    }
                    Haptics.light()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: freq.icon)
                            .font(.system(size: 16, weight: .medium))
                        
                        Text(freq.displayName)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(selected == freq ? DS.Colors.text : DS.Colors.subtext)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected == freq ? DS.Colors.surface2 : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selected == freq ? DS.Colors.accent.opacity(0.4) : DS.Colors.grid.opacity(0.5), lineWidth: 1)
                    )
                }
            }
        }
    }
}
