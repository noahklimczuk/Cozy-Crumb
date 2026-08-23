//
//  GroceriesView.swift
//  Cozy Crumb
//
//  The shell for the two halves of shopping: the week you're planning, and
//  the list you take to the shop.
//
//  They live in one tab because they're one loop — plan the week, press a
//  button, walk the aisles — and splitting them across tabs would hide the
//  connection.
//
//  The switch between the two used to sit in the navigation bar's principal
//  slot. With the bar hidden it moves into each half's own `ScreenHeader`,
//  under the title, which is where the header's `below:` strip is for. That
//  means this shell owns the mode and hands a binding down rather than drawing
//  anything itself — whichever half is on screen draws the switch, so it can
//  sit in the same block as that half's title and controls.
//

import Foundation
// SwiftData is only used by the preview's `.modelContainer`, but SE-0444
// means the import still has to be here for it to resolve.
import SwiftData
import SwiftUI

/// Which half of the Groceries tab is showing.
enum GroceryTabMode: String, CaseIterable, Identifiable {
    case plan
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan: "This week"
        case .list: "Shopping"
        }
    }
}

/// The switch between the two halves. One definition, drawn by both, so they
/// can't drift into two slightly different segmented controls.
struct GroceryModePicker: View {
    @Binding var mode: GroceryTabMode

    var body: some View {
        Picker("View", selection: $mode) {
            ForEach(GroceryTabMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Which list")
    }
}

struct GroceriesView: View {
    @State private var mode: GroceryTabMode = .list

    var body: some View {
        NavigationStack {
            switch mode {
            case .plan: MealPlanView(mode: $mode)
            case .list: ShoppingListView(mode: $mode)
            }
        }
    }
}

#Preview("Groceries") {
    GroceriesView()
        .modelContainer(PreviewData.groceriesContainer)
}
