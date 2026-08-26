//
//  IngredientDensity.swift
//  Cozy Crumb
//
//  How much a cup of something weighs.
//
//  This exists so that switching a recipe to metric can answer in grams
//  instead of millilitres. A metric kitchen weighs its dry goods: "125 g
//  flour" is what a European recipe says, and "240 ml flour" is not a thing
//  anybody has ever measured. But a cup is a volume, and turning it into a
//  weight needs to know what is *in* the cup — a cup of flour is 125 g, a cup
//  of granulated sugar is 200 g, a cup of honey is 340 g. Without the
//  ingredient there is no answer, only an average that is wrong for
//  everything.
//
//  Figures are the King Arthur Baking ingredient weight chart where it covers
//  the ingredient, and USDA densities elsewhere. They are approximations by
//  nature — flour especially, which varies by how it was scooped — and that is
//  fine: a recipe scaled to metric wants to be usefully close, and a cook who
//  needs better than ±5% on flour is already weighing it.
//
//  Matching is by keyword against the ingredient's name, longest first, so
//  "brown sugar" wins over "sugar" and "almond flour" over "flour".
//

import Foundation

nonisolated enum IngredientDensity {

    /// Grams in one US cup (236.6 ml), by ingredient keyword.
    ///
    /// Ordered longest-keyword-first at lookup time rather than here, so
    /// entries can be added in whatever grouping reads best.
    private static let table: [String: Double] = [
        // Liquids
        "water": 236, "milk": 244, "buttermilk": 245, "cream": 238,
        "stock": 240, "broth": 240, "juice": 248, "wine": 236,
        "yoghurt": 245, "yogurt": 245, "sour cream": 240,
        "coconut milk": 240, "passata": 250, "tomato sauce": 245,

        // Fats
        "butter": 227, "olive oil": 216, "vegetable oil": 218, "oil": 218,
        "peanut butter": 258, "tahini": 240, "mayonnaise": 220,

        // Flours and dry baking
        "plain flour": 125, "all-purpose flour": 125, "bread flour": 127,
        "wholemeal flour": 120, "whole wheat flour": 120, "self-raising flour": 125,
        "almond flour": 96, "cornflour": 120, "cornstarch": 120, "flour": 125,
        "rolled oats": 90, "oats": 90, "breadcrumbs": 108,
        "cocoa powder": 85, "cocoa": 85, "desiccated coconut": 85,

        // Sugars
        "icing sugar": 120, "powdered sugar": 120, "confectioners sugar": 120,
        "brown sugar": 213, "caster sugar": 200, "granulated sugar": 200,
        "sugar": 200, "honey": 340, "maple syrup": 322, "golden syrup": 340,
        "molasses": 337, "treacle": 337,

        // Grains and pulses
        "rice": 185, "couscous": 173, "quinoa": 170, "lentils": 192,
        "chickpeas": 164, "black beans": 172, "pasta": 100,

        // Dairy and solids by volume
        "parmesan": 100, "cheddar": 113, "mozzarella": 112, "cheese": 113,
        "chocolate chips": 170, "chocolate": 170,
        "raisins": 145, "sultanas": 145, "dates": 147,
        "walnuts": 117, "almonds": 143, "pecans": 109, "nuts": 120,

        // Seasonings measured by volume often enough to matter
        "table salt": 292, "kosher salt": 218, "sea salt": 256, "salt": 273,
        "baking powder": 192, "baking soda": 220, "bicarbonate of soda": 220,
        "ground cinnamon": 132, "cinnamon": 132, "ground cumin": 100,
    ]

    /// Sorted once: longest keyword first, so a specific match beats a generic
    /// one no matter what order the table above is written in.
    private static let byLength: [(keyword: String, grams: Double)] = {
        table
            .map { (keyword: $0.key, grams: $0.value) }
            .sorted { $0.keyword.count > $1.keyword.count }
    }()

    /// Grams in one cup of `ingredient`, or nil when it isn't recognised.
    ///
    /// nil is a real answer, not a failure: it means the conversion should
    /// stay in millilitres rather than invent a weight.
    static func gramsPerCup(of ingredient: String?) -> Double? {
        guard let ingredient, !ingredient.isEmpty else { return nil }
        let name = ingredient.lowercased()
        return byLength.first { name.contains($0.keyword) }?.grams
    }
}
