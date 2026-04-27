import SwiftUI

// ============================================================
// MARK: - Full Category Editor (Phase 4 — UI rebuild 2026-04-27)
// ============================================================
//
// Polished editor sheet for adding / editing a custom category.
// Replaces the stock `Form` layout with the app's design system
// (`DS.Card`, `DS.Colors`, `DS.Typography`) and inlines the icon
// grid + colour swatches so users never leave the sheet.
//
// Layout:
//   ┌────────── Live preview chip (matches chat/list rendering) ─┐
//   │ NAME card        — text field + live duplicate validation  │
//   │ ICON card        — 4-col scrollable grid, tap to select    │
//   │ COLOR card       — preset swatches + custom ColorPicker    │
//
// Save flow is unchanged: writes to the bound `customCategories`
// list, then notifies via `onSave?(model)`. The Settings + in-flow
// wrappers do their own side-effect reconciliation.
// ============================================================

struct FullCategoryEditor: View {
    @Environment(\.dismiss) var dismiss
    @Binding var customCategories: [CustomCategoryModel]

    let editingCategory: CustomCategoryModel?
    let onSave: ((CustomCategoryModel) -> Void)?

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColor: Color = Color(hex: "AF52DE") ?? .purple

    init(customCategories: Binding<[CustomCategoryModel]>,
         editingCategory: CustomCategoryModel? = nil,
         onSave: ((CustomCategoryModel) -> Void)? = nil) {
        self._customCategories = customCategories
        self.editingCategory = editingCategory
        self.onSave = onSave

        if let category = editingCategory {
            _name = State(initialValue: category.name)
            _selectedIcon = State(initialValue: category.icon)
            _selectedColor = State(initialValue: category.color)
        }
    }

    // MARK: - Validation

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// nil when input is valid, otherwise an error message.
    private var validationError: String? {
        if trimmedName.isEmpty { return nil }  // empty handled by disabled Add button
        let lower = trimmedName.lowercased()

        // Conflict with built-in
        let systemNames = Category.allCases.map { $0.title.lowercased() }
        if systemNames.contains(lower) { return "Reserved by a built-in category" }

        // Conflict with another custom (allow same-name save when editing)
        let conflict = customCategories.contains { existing in
            existing.id != (editingCategory?.id ?? "") && existing.name.lowercased() == lower
        }
        if conflict { return "A category with this name already exists" }

        return nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && validationError == nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    previewChip
                    nameCard
                    iconCard
                    colorCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle(editingCategory == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingCategory == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Live preview chip

    private var previewChip: some View {
        VStack(spacing: 10) {
            Text("PREVIEW")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Image(systemName: selectedIcon)
                    .font(.system(size: 16, weight: .semibold))
                Text(trimmedName.isEmpty ? "Category Name" : trimmedName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(selectedColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(selectedColor.opacity(0.16))
            )
            .overlay(
                Capsule().strokeBorder(selectedColor.opacity(0.35), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Colors.surface2)
            )
        }
    }

    // MARK: - Name card

    private var nameCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Name")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                TextField("e.g. Coffee", text: $name)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Colors.surface2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(
                                validationError == nil
                                    ? Color.clear
                                    : DS.Colors.danger.opacity(0.7),
                                lineWidth: 1
                            )
                    )

                if let error = validationError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(DS.Colors.danger)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: validationError)
        }
    }

    // MARK: - Icon card

    private var iconCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Icon")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Text(selectedIcon)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Colors.subtext)
                        .lineLimit(1)
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                    spacing: 10
                ) {
                    ForEach(Self.iconChoices, id: \.self) { icon in
                        Button {
                            Haptics.selection()
                            selectedIcon = icon
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(selectedIcon == icon ? selectedColor : DS.Colors.subtext)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedIcon == icon
                                              ? selectedColor.opacity(0.18)
                                              : DS.Colors.surface2)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            selectedIcon == icon ? selectedColor : Color.clear,
                                            lineWidth: 1.5
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Color card

    private var colorCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Color")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6),
                    spacing: 10
                ) {
                    ForEach(Self.colorChoices, id: \.self) { hex in
                        let swatch = Color(hex: hex) ?? .purple
                        let isSelected = selectedColor.toHex().lowercased() == hex.lowercased()
                        Button {
                            Haptics.selection()
                            selectedColor = swatch
                        } label: {
                            Circle()
                                .fill(swatch)
                                .frame(height: 36)
                                .overlay(
                                    Circle()
                                        .strokeBorder(DS.Colors.surface, lineWidth: 2)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(isSelected ? DS.Colors.text : Color.clear, lineWidth: 2)
                                        .padding(-1)
                                )
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .opacity(isSelected ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().foregroundStyle(DS.Colors.grid)

                HStack {
                    Text("Custom")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }

        let category = CustomCategoryModel(
            id: editingCategory?.id ?? UUID().uuidString,
            name: trimmedName,
            icon: selectedIcon,
            colorHex: selectedColor.toHex(),
            sortOrder: editingCategory?.sortOrder ?? 0
        )

        if let index = customCategories.firstIndex(where: { $0.id == category.id }) {
            customCategories[index] = category
        } else {
            customCategories.append(category)
        }

        onSave?(category)
        Haptics.success()
        dismiss()
    }

    // MARK: - Choices

    /// 48 SF Symbols organised loosely from generic → food → transport →
    /// home → shopping → media → health → education → money → tech → misc.
    static let iconChoices: [String] = [
        "tag.fill", "star.fill", "heart.fill", "flag.fill", "bookmark.fill", "sparkles",
        "cart.fill", "basket.fill", "fork.knife", "cup.and.saucer.fill", "wineglass.fill", "birthday.cake.fill",
        "car.fill", "bus.fill", "tram.fill", "airplane", "bicycle", "fuelpump.fill",
        "house.fill", "bed.double.fill", "lightbulb.fill", "wrench.and.screwdriver.fill", "leaf.fill", "pawprint.fill",
        "bag.fill", "gift.fill", "creditcard.fill", "tshirt.fill", "shippingbox.fill", "gift.circle.fill",
        "film.fill", "tv.fill", "gamecontroller.fill", "music.note", "headphones", "book.fill",
        "cross.case.fill", "pill.fill", "figure.walk", "dumbbell.fill", "bandage.fill", "stethoscope",
        "graduationcap.fill", "pencil", "backpack.fill", "studentdesk", "books.vertical.fill", "lightbulb.max.fill",
        "dollarsign.circle.fill", "eurosign.circle.fill", "bitcoinsign.circle.fill", "banknote.fill", "chart.line.uptrend.xyaxis", "briefcase.fill"
    ]

    /// Twelve curated swatches that read well on both light and dark surfaces.
    static let colorChoices: [String] = [
        "338CFF", // electric blue (app accent)
        "AF52DE", // purple
        "FF2D55", // pink
        "FF3B30", // red
        "FF9500", // orange
        "FFCC00", // yellow
        "34C759", // green
        "00C7BE", // teal
        "5AC8FA", // sky
        "A0522D", // brown / coffee
        "8E8E93", // grey
        "1D1D1F"  // near-black
    ]
}
