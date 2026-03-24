import SwiftUI

// MARK: - Full Category Manager
struct FullCategoryManager: View {
    @Binding var customCategories: [CustomCategoryModel]
    let onSave: ((CustomCategoryModel) -> Void)?  // ← Updated type
    
    @State private var showAddCategory = false
    @State private var editingCategory: CustomCategoryModel?
    
    init(customCategories: Binding<[CustomCategoryModel]>, onSave: ((CustomCategoryModel) -> Void)? = nil) {
        self._customCategories = customCategories
        self.onSave = onSave
    }
    
    // Default categories (read-only)
    let defaultCategories: [(name: String, icon: String, color: Color)] = [
        ("Groceries", "cart.fill", .green),
        ("Rent", "house.fill", .orange),
        ("Bills", "doc.text.fill", .red),
        ("Transport", "car.fill", .blue),
        ("Health", "heart.fill", Color(red: 1.0, green: 0.23, blue: 0.19)),
        ("Education", "book.fill", Color(red: 0.35, green: 0.78, blue: 0.98)),
        ("Dining", "fork.knife", Color(red: 1.0, green: 0.18, blue: 0.33)),
        ("Shopping", "bag.fill", Color(red: 0.69, green: 0.32, blue: 0.87)),
        ("Other", "questionmark.circle.fill", .gray)
    ]
    
    var body: some View {
        List {
            // Default Categories
            Section("Default Categories") {
                ForEach(defaultCategories, id: \.name) { category in
                    HStack(spacing: 12) {
                        Image(systemName: category.icon)
                            .font(.system(size: 24))
                            .foregroundColor(category.color)
                            .frame(width: 40, height: 40)
                            .background(category.color.opacity(0.2))
                            .cornerRadius(8)
                        
                        Text(category.name)
                        
                        Spacer()
                        
                        Circle()
                            .fill(category.color)
                            .frame(width: 20, height: 20)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            // Custom Categories
            Section {
                ForEach(customCategories) { category in
                    Button {
                        editingCategory = category
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .font(.system(size: 24))
                                .foregroundColor(category.color)
                                .frame(width: 40, height: 40)
                                .background(category.color.opacity(0.2))
                                .cornerRadius(8)
                            
                            Text(category.name)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Circle()
                                .fill(category.color)
                                .frame(width: 20, height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteCategories)
                
                Button {
                    showAddCategory = true
                } label: {
                    Label("Add Custom Category", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Custom Categories")
            }
        }
        .navigationTitle("Manage Categories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddCategory) {
            FullCategoryEditor(customCategories: $customCategories, onSave: onSave)
        }
        .sheet(item: $editingCategory) { category in
            FullCategoryEditor(customCategories: $customCategories, editingCategory: category, onSave: onSave)
        }
    }
    
    private func deleteCategories(at offsets: IndexSet) {
        customCategories.remove(atOffsets: offsets)
    }
}

#Preview {
    NavigationView {
        FullCategoryManager(customCategories: .constant([
            CustomCategoryModel(name: "Coffee", icon: "cup.and.saucer.fill", colorHex: "A0522D"),
            CustomCategoryModel(name: "Pets", icon: "pawprint.fill", colorHex: "FF6B6B")
        ]))
    }
}
