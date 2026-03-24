// MARK: - Add Recurring Sheet (Professional - Fixed)

/*import SwiftUI

private struct AddRecurringSheet: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("app.currency") private var selectedCurrency: String = "EUR"
    
    @State private var amount: String = ""
    @State private var selectedCategory: Category = .groceries
    @State private var note: String = ""
    @State private var selectedPaymentMethod: PaymentMethod = .card
    @State private var selectedType: TransactionType = .expense
    @State private var selectedFrequency: RecurringFrequency = .monthly
    @State private var startDate: Date = Date()
    @State private var hasEndDate: Bool = false
    @State private var endDate: Date = Date()
    
    private var currencySymbol: String {
        switch selectedCurrency {
        case "USD": return "$"
        case "GBP": return "£"
        case "JPY": return "¥"
        case "CAD": return "C$"
        default: return "€"
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header Section
                    VStack(spacing: 20) {
                        // Type Selector
                        HStack(spacing: 12) {
                            typeButton(.expense, icon: "minus", title: "Expense")
                            typeButton(.income, icon: "plus", title: "Income")
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Amount Input
                        VStack(spacing: 8) {
                            Text("Amount")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            HStack(spacing: 8) {
                                Text(currencySymbol)
                                    .font(.system(size: 32, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                
                                TextField("0.00", text: $amount)
                                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(Color(uiColor: .label))
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    Divider().padding(.vertical, 24)
                    
                    // Details Section
                    VStack(spacing: 20) {
                        detailRow(title: "Category") {
                            categoryPicker
                        }
                        
                        detailRow(title: "Note (Optional)") {
                            TextField("Add a note...", text: $note)
                                .font(.system(size: 15))
                                .padding(12)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        
                        detailRow(title: "Payment Method") {
                            paymentMethodPicker
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Divider().padding(.vertical, 24)
                    
                    // Frequency Section
                    VStack(spacing: 20) {
                        detailRow(title: "Frequency") {
                            frequencyPicker
                        }
                        
                        detailRow(title: "Start Date") {
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        
                        detailRow(title: "End Date") {
                            HStack {
                                Toggle("", isOn: $hasEndDate)
                                    .labelsHidden()
                                
                                if hasEndDate {
                                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 100)
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Add Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRecurring()
                    }
                    .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if canSave {
                    Button {
                        saveRecurring()
                    } label: {
                        Text("Save Recurring Transaction")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                    .background(Color(uiColor: .systemBackground))
                }
            }
        }
    }
    
    // MARK: - Pickers
    
    private var categoryPicker: some View {
        Menu {
            ForEach(store.allCategories, id: \.self) { category in
                Button {
                    selectedCategory = category
                } label: {
                    Label(category.title, systemImage: category.icon)
                }
            }
        } label: {
            pickerLabel(icon: selectedCategory.icon, text: selectedCategory.title)
        }
    }
    
    private var paymentMethodPicker: some View {
        Menu {
            ForEach(PaymentMethod.allCases, id: \.self) { method in
                Button {
                    selectedPaymentMethod = method
                } label: {
                    Label(method.rawValue, systemImage: method.icon)
                }
            }
        } label: {
            pickerLabel(icon: selectedPaymentMethod.icon, text: selectedPaymentMethod.rawValue)
        }
    }
    
    private var frequencyPicker: some View {
        Menu {
            ForEach(RecurringFrequency.allCases, id: \.self) { frequency in
                Button {
                    selectedFrequency = frequency
                } label: {
                    Label(frequency.displayName, systemImage: frequency.icon)
                }
            }
        } label: {
            pickerLabel(icon: selectedFrequency.icon, text: selectedFrequency.displayName)
        }
    }
    
    private func pickerLabel(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color(uiColor: .label))
                .frame(width: 28, height: 28)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color(uiColor: .label))
            
            Spacer()
            
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Type Button
    
    private func typeButton(_ type: TransactionType, icon: String, title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "\(icon).circle")
                    .font(.system(size: 18))
                
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(selectedType == type ? Color(uiColor: .label) : Color(uiColor: .secondaryLabel))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                selectedType == type ? Color(uiColor: .secondarySystemBackground) : Color.clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        selectedType == type ? Color(uiColor: .separator) : Color(uiColor: .separator).opacity(0.5),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Detail Row
    
    private func detailRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
            
            content()
        }
    }
    
    // MARK: - Validation & Save
    
    private var canSave: Bool {
        guard let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")),
              amountValue > 0 else {
            return false
        }
        return true
    }
    
    private func saveRecurring() {
        guard let amountValue = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }
        
        let amountInCents = Int(amountValue * 100)
        
        let recurring = RecurringTransaction(
            amount: amountInCents,
            category: selectedCategory,
            note: note.isEmpty ? "-" : note,
            paymentMethod: selectedPaymentMethod,
            type: selectedType,
            frequency: selectedFrequency,
            startDate: startDate,
            endDate: hasEndDate ? endDate : nil
        )
        
        store.recurringTransactions.append(recurring)
        dismiss()
    }
}*/
