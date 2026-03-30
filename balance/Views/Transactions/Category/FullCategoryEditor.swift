import SwiftUI

// MARK: - Full Category Editor با Icon و Color
struct FullCategoryEditor: View {
    @Environment(\.dismiss) var dismiss
    @Binding var customCategories: [CustomCategoryModel]
    
    let editingCategory: CustomCategoryModel?
    let onSave: ((CustomCategoryModel) -> Void)?  // ← برگردونه کل model
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColor: Color = .purple
    @State private var showIconPicker = false
    @State private var showDuplicateAlert = false
    
    init(customCategories: Binding<[CustomCategoryModel]>, editingCategory: CustomCategoryModel? = nil, onSave: ((CustomCategoryModel) -> Void)? = nil) {
        self._customCategories = customCategories
        self.editingCategory = editingCategory
        self.onSave = onSave
        
        if let category = editingCategory {
            _name = State(initialValue: category.name)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColor = State(initialValue: category.color)
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Name
                Section("Category Name") {
                    TextField("e.g. Coffee", text: $name)
                }
                
                // Icon
                Section("Icon") {
                    Button {
                        showIconPicker = true
                    } label: {
                        HStack {
                            Image(systemName: selectedIcon)
                                .font(.system(size: 32))
                                .foregroundColor(selectedColor)
                                .frame(width: 50, height: 50)
                                .background(selectedColor.opacity(0.2))
                                .cornerRadius(10)
                            
                            Text("Choose Icon")
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Color
                Section("Color") {
                    ColorPicker("Category Color", selection: $selectedColor, supportsOpacity: false)
                }
                
                // Preview
                Section("Preview") {
                    HStack {
                        Image(systemName: selectedIcon)
                            .foregroundColor(selectedColor)
                        Text(name.isEmpty ? "Category Name" : name)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(selectedColor.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .navigationTitle(editingCategory == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingCategory == nil ? "Add" : "Save") {
                        saveCategory()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerSheet(selectedIcon: $selectedIcon, selectedColor: selectedColor)
            }
            .alert("Duplicate Name", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("A category with this name already exists. Please choose a different name.")
            }
        }
    }
    
    private func saveCategory() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // Duplicate-name guard: reject if another custom category already has this name
        // (allow saving the same name back when editing — only block true conflicts)
        let isRename = editingCategory != nil && editingCategory!.name != trimmedName
        let isNew = editingCategory == nil
        if isRename || isNew {
            let lowerName = trimmedName.lowercased()
            let conflict = customCategories.contains { existing in
                existing.id != (editingCategory?.id ?? "") && existing.name.lowercased() == lowerName
            }
            // Also check system category names
            let systemNames = Category.allCases.map { $0.title.lowercased() }
            if conflict || systemNames.contains(lowerName) {
                showDuplicateAlert = true
                return
            }
        }

        let category = CustomCategoryModel(
            id: editingCategory?.id ?? UUID().uuidString,
            name: trimmedName,
            icon: selectedIcon,
            colorHex: selectedColor.toHex()
        )

        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
        } else {
            customCategories.append(category)
        }

        onSave?(category)

        dismiss()
    }
}

// MARK: - Icon Picker
struct IconPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIcon: String
    let selectedColor: Color
    
    let icons = [
        "tag.fill", "star.fill", "heart.fill", "cart.fill", "basket.fill",
        "fork.knife", "cup.and.saucer.fill", "wineglass.fill",
        "car.fill", "bus.fill", "airplane", "bicycle", "fuelpump.fill",
        "house.fill", "bed.double.fill", "lamp.desk.fill", "lightbulb.fill",
        "bag.fill", "gift.fill", "creditcard.fill", "tshirt.fill",
        "film.fill", "tv.fill", "gamecontroller.fill", "music.note",
        "heart.text.square.fill", "cross.case.fill", "pill.fill", "figure.walk",
        "book.fill", "graduationcap.fill", "pencil", "backpack.fill",
        "dollarsign.circle.fill", "eurosign.circle.fill", "bitcoinsign.circle.fill",
        "briefcase.fill", "laptopcomputer", "desktopcomputer",
        "phone.fill", "envelope.fill", "message.fill",
        "pawprint.fill", "leaf.fill", "flame.fill", "drop.fill",
        "moon.stars.fill", "sun.max.fill", "cloud.fill", "snowflake"
    ]
    
    let columns = Array(repeating: GridItem(.flexible()), count: 4)
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(icons, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                            dismiss()
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 28))
                                .foregroundColor(selectedIcon == icon ? selectedColor : .primary)
                                .frame(width: 60, height: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedIcon == icon ? selectedColor.opacity(0.2) : Color.gray.opacity(0.1))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedIcon == icon ? selectedColor : Color.clear, lineWidth: 2)
                                )
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
