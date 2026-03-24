# Balance App — UI Redesign v2: Design Direction & Implementation Guide

## Current Design Problems

### 1. Visual Heaviness
- Every card uses `DS.Colors.surface` (secondarySystemBackground) with a **1px stroke border** — this creates a grid of outlined boxes that feel rigid and dated
- The dark theme default (`@AppStorage("app.theme") = "dark"`) makes the entire UI feel dense and heavy
- Payment method cards use thick 2px borders when selected with dark gradient backgrounds

### 2. Poor Typography Hierarchy
- Title font is only 18pt — not bold enough for a finance app's key numbers
- Body and caption sizes (14pt, 12pt) are too close together — weak visual distinction
- The amount input field (16pt monospaced) doesn't feel like a hero element

### 3. Cramped Spacing
- Card internal padding is only 14px — feels tight
- Section spacing is 14px between cards — everything runs together
- Category chips have only 9px vertical padding — too small for comfortable tapping

### 4. Outdated Card Style
- Every card has an identical look: background + 1px stroke border
- No shadow depth hierarchy — flat and monotonous
- The border-heavy approach looks like 2019-era iOS design

### 5. Weak Color System
- Accent color `0x667EEA` (purple) is used everywhere without variation
- The expense (red) / income (green) toggle uses raw Color.red/Color.green — harsh and unrefined
- No soft tinting or gradient sophistication

### 6. Form UX Issues
- The Expense/Income toggle uses small 14pt text in hard red/green rectangles — feels aggressive
- Amount input blends into the form instead of standing out as the hero element
- Category chips are small and hard to tap
- Dividers between every section add visual noise

---

## New Design System Definition

### Color Palette (Light Theme)

```swift
// Backgrounds
background:     Color(red: 0.97, green: 0.97, blue: 0.98)  // #F7F7FA — soft off-white
surface:        Color.white                                   // Pure white cards
surfaceSecondary: Color(red: 0.95, green: 0.95, blue: 0.97)  // #F2F2F7 — input fields

// Text
textPrimary:    Color(red: 0.11, green: 0.11, blue: 0.12)    // #1C1C1F — near black
textSecondary:  Color(red: 0.56, green: 0.56, blue: 0.58)    // #8F8F94 — muted
textTertiary:   Color(red: 0.72, green: 0.72, blue: 0.74)    // #B8B8BC — placeholder

// Accent
accent:         Color(red: 0.27, green: 0.35, blue: 0.96)    // #4559F5 — refined blue
accentLight:    Color(red: 0.27, green: 0.35, blue: 0.96).opacity(0.08)

// Semantic
positive:       Color(red: 0.20, green: 0.78, blue: 0.55)    // #34C78C — soft green
negative:       Color(red: 0.96, green: 0.32, blue: 0.35)    // #F55259 — soft red
warning:        Color(red: 1.00, green: 0.72, blue: 0.27)    // #FFB845 — warm amber

// Borders & Dividers
border:         Color(red: 0.91, green: 0.91, blue: 0.93)    // #E8E8ED — very subtle
```

### Typography Scale

```swift
largeTitle:  .system(size: 28, weight: .bold, design: .rounded)
title:       .system(size: 20, weight: .semibold, design: .rounded)
headline:    .system(size: 17, weight: .semibold, design: .rounded)
body:        .system(size: 15, weight: .regular, design: .rounded)
callout:     .system(size: 14, weight: .medium, design: .rounded)
caption:     .system(size: 13, weight: .regular, design: .rounded)
heroAmount:  .system(size: 42, weight: .bold, design: .rounded)
number:      .system(size: 17, weight: .semibold, design: .monospaced)
```

### Spacing

```swift
xs:  4
sm:  8
md:  12
lg:  16
xl:  20
xxl: 28
xxxl: 36
```

### Corner Radius

```swift
sm:   10
md:   14
lg:   20
xl:   24
pill:  999
```

### Shadows

```swift
// Card shadow — subtle elevation
cardShadow:   color: .black.opacity(0.04), radius: 12, y: 4

// Elevated shadow — buttons, selected states
elevatedShadow: color: .black.opacity(0.08), radius: 16, y: 6

// Soft glow — accent elements
accentGlow:   color: accent.opacity(0.20), radius: 12, y: 4
```

### Card Style (New)
- **No borders** — shadows only for depth
- White background on off-white page
- 18px internal padding
- 20px corner radius
- Subtle shadow for elevation

### Button Styles
- **Primary**: Filled accent color, white text, 14px corner radius, 52px height
- **Secondary**: White background, accent text, subtle border
- **Segmented Control**: Pill-shaped, sliding indicator, no borders

### Input Fields
- Background: surfaceSecondary (#F2F2F7)
- No border — relies on background contrast
- 14px corner radius
- 14px padding

---

## Affected Files

### Primary (must update):
1. `ContentView.swift` — DS enum, TransactionFormCard, AddTransactionSheet, EditTransactionSheet, DashboardView, all card components
2. Default theme should switch to "light"

### Secondary (should update for consistency):
3. All Dashboard card views in `Views/Dashboard/`
4. All Account views in `Views/Account/`
5. All Chart views in `Views/Charts/`
6. Profile and Settings views

---

## Implementation Strategy

### Phase 1: Design System Core (this update)
- Update DS.Colors for light theme
- Update DS.Typography with better hierarchy
- Update DS.Card to use shadows instead of borders
- Update DS.PrimaryButton, DS.TextFieldStyle
- Add new reusable components

### Phase 2: Add Transaction Screen (this update)
- Redesign TransactionFormCard
- Redesign AddTransactionSheet layout
- Modern segmented control
- Hero amount input
- Better category chips
- Cleaner payment method selector

### Phase 3: Global Propagation (follow-up)
- Dashboard cards
- Transaction list
- Budget view
- Settings/Profile
- Charts

---

## Notes for Further Polishing
- Consider adding subtle haptic feedback on theme transitions
- The category tint colors work well — keep them but use at lower opacity (0.08-0.12) for chip backgrounds
- Payment method icons should use SF Symbols with .light weight for unselected, .semibold for selected
- Date picker should use the compact style with a custom label for consistency
- Consider adding a subtle gradient on the page background (white to very light gray) for depth
- Tab bar should be updated to match — white background with subtle top border
