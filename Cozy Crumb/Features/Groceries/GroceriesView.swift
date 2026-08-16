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

import Foundation
// SwiftData is only used by the preview's `.modelContainer`, but SE-0444
// means the import still has to be here for it to resolve.
import SwiftData
import SwiftUI

struct GroceriesView: View {
    private enum Mode: String, CaseIterable, Identifiable {
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

    @State private var mode: Mode = .list

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .plan: MealPlanView()
                case .list: ShoppingListView()
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
            }
        }
    }
}

#Preview("Groceries") {
    GroceriesView()
        .modelContainer(PreviewData.groceriesContainer)
}
