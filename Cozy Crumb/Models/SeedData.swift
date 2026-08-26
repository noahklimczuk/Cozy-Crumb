//
//  SeedData.swift
//  Cozy Crumb
//
//  Five realistic recipes for previews to work with.
//
//  These used to be installed into a fresh store on first launch, so a new
//  cookbook arrived with somebody else's recipes in it. It doesn't any more: a
//  new install opens empty, and the empty state already says what to do about
//  that. The samples stay because every preview in the app is built from them.
//

import Foundation
import SwiftData
import os

enum SeedData {

    // MARK: - Recipes

    static func bananaBread(collections: [RecipeCollection] = []) -> Recipe {
        Recipe(
            title: "Brown Butter Banana Bread",
            summary: "A loaf that makes the whole flat smell like a bakery.",
            sourceName: "Mom's index card",
            sourceKind: .manual,
            servings: 8,
            prepMinutes: 20,
            cookMinutes: 55,
            ingredients: [
                Ingredient(order: 0, rawText: "115 g unsalted butter", quantity: 115, unit: "g", name: "unsalted butter", groceryCategory: .dairy),
                Ingredient(order: 1, rawText: "3 very ripe bananas", quantity: 3, unit: "piece", name: "bananas", note: "very ripe", groceryCategory: .produce),
                Ingredient(order: 2, rawText: "150 g light brown sugar", quantity: 150, unit: "g", name: "light brown sugar", groceryCategory: .pantry),
                Ingredient(order: 3, rawText: "2 large eggs", quantity: 2, unit: "piece", name: "eggs", note: "large", groceryCategory: .dairy),
                Ingredient(order: 4, rawText: "1 tsp vanilla extract", quantity: 1, unit: "tsp", name: "vanilla extract", groceryCategory: .pantry),
                Ingredient(order: 5, rawText: "190 g plain flour", quantity: 190, unit: "g", name: "plain flour", groceryCategory: .pantry),
                Ingredient(order: 6, rawText: "1 tsp baking soda", quantity: 1, unit: "tsp", name: "baking soda", groceryCategory: .pantry),
                Ingredient(order: 7, rawText: "1/2 tsp fine sea salt", quantity: 0.5, unit: "tsp", name: "fine sea salt", groceryCategory: .pantry)
            ],
            steps: [
                RecipeStep(order: 0, text: "Melt the butter in a light-coloured pan over medium heat, swirling until it foams and the milk solids turn nutty brown. Pour into a bowl and let it cool for 10 minutes.", durationSeconds: 600),
                RecipeStep(order: 1, text: "Heat the oven to 175°C and line a 900g loaf tin with baking paper."),
                RecipeStep(order: 2, text: "Mash the bananas into the cooled butter, then whisk in the sugar, eggs and vanilla until glossy."),
                RecipeStep(order: 3, text: "Fold in the flour, baking soda and salt. Stop the moment you stop seeing dry flour — overmixing makes it tough."),
                RecipeStep(order: 4, text: "Scrape into the tin and bake for 50 to 55 minutes, until a skewer comes out with a few damp crumbs.", durationSeconds: 3300),
                RecipeStep(order: 5, text: "Cool in the tin for 15 minutes before turning out.", durationSeconds: 900)
            ],
            collections: collections,
            tags: ["baking", "breakfast", "make ahead"],
            isFavorite: true,
            rating: 5
        )
    }

    static func misoSalmon(collections: [RecipeCollection] = []) -> Recipe {
        Recipe(
            title: "Weeknight Miso Salmon",
            summary: "Fifteen minutes, one tray, almost no washing up.",
            sourceURL: URL(string: "https://example.com/miso-salmon"),
            sourceName: "Saved from the web",
            sourceKind: .web,
            servings: 2,
            prepMinutes: 5,
            cookMinutes: 12,
            ingredients: [
                Ingredient(order: 0, rawText: "2 salmon fillets, skin on", quantity: 2, unit: "piece", name: "salmon fillets", note: "skin on", groceryCategory: .meat),
                Ingredient(order: 1, rawText: "2 tbsp white miso paste", quantity: 2, unit: "tbsp", name: "white miso paste", groceryCategory: .condiment),
                Ingredient(order: 2, rawText: "1 tbsp mirin", quantity: 1, unit: "tbsp", name: "mirin", groceryCategory: .condiment),
                Ingredient(order: 3, rawText: "1 tbsp soy sauce", quantity: 1, unit: "tbsp", name: "soy sauce", groceryCategory: .condiment),
                Ingredient(order: 4, rawText: "1 tsp honey", quantity: 1, unit: "tsp", name: "honey", groceryCategory: .pantry),
                Ingredient(order: 5, rawText: "2 spring onions, sliced", quantity: 2, unit: "piece", name: "spring onions", note: "sliced", groceryCategory: .produce),
                Ingredient(order: 6, rawText: "Steamed rice, to serve", name: "steamed rice", note: "to serve", groceryCategory: .pantry)
            ],
            steps: [
                RecipeStep(order: 0, text: "Heat the grill to high and line a small tray with foil."),
                RecipeStep(order: 1, text: "Whisk the miso, mirin, soy and honey into a smooth paste."),
                RecipeStep(order: 2, text: "Pat the salmon dry and spread the glaze thickly over the top of each fillet."),
                RecipeStep(order: 3, text: "Grill for 8 to 10 minutes, until the glaze is bubbling and just catching at the edges and the salmon flakes.", durationSeconds: 540),
                RecipeStep(order: 4, text: "Scatter with spring onions and serve over rice.")
            ],
            collections: collections,
            tags: ["quick", "fish", "weeknight"],
            rating: 4
        )
    }

    static func cacioEPepe(collections: [RecipeCollection] = []) -> Recipe {
        Recipe(
            title: "Proper Cacio e Pepe",
            summary: "Four ingredients, and every one of them matters.",
            sourceName: "@pastagrannies",
            sourceKind: .social,
            servings: 2,
            prepMinutes: 5,
            cookMinutes: 15,
            ingredients: [
                Ingredient(order: 0, rawText: "200 g tonnarelli or spaghetti", quantity: 200, unit: "g", name: "tonnarelli", groceryCategory: .pantry),
                Ingredient(order: 1, rawText: "100 g Pecorino Romano, finely grated", quantity: 100, unit: "g", name: "Pecorino Romano", note: "finely grated", groceryCategory: .dairy),
                Ingredient(order: 2, rawText: "2 tsp black peppercorns, coarsely cracked", quantity: 2, unit: "tsp", name: "black peppercorns", note: "coarsely cracked", groceryCategory: .pantry),
                Ingredient(order: 3, rawText: "Salt, for the pasta water", name: "salt", note: "for the pasta water", groceryCategory: .pantry)
            ],
            steps: [
                RecipeStep(order: 0, text: "Boil the pasta in less water than usual and salt it lightly — you want the water starchy, and the pecorino is already salty."),
                RecipeStep(order: 1, text: "Toast the cracked pepper in a dry wide pan for about a minute, until it smells fragrant.", durationSeconds: 60),
                RecipeStep(order: 2, text: "Ladle a little pasta water into the pepper pan and let it bubble."),
                RecipeStep(order: 3, text: "Mix the pecorino with a few spoons of cooled pasta water into a smooth paste. If it's too hot it will split."),
                RecipeStep(order: 4, text: "Drain the pasta two minutes early, finish it in the pepper pan, then take it off the heat and stir the cheese paste through until glossy.")
            ],
            collections: collections,
            tags: ["pasta", "quick", "vegetarian"],
            importConfidence: 0.72
        )
    }

    static func chickpeaCurry(collections: [RecipeCollection] = []) -> Recipe {
        Recipe(
            title: "Chickpea & Spinach Curry",
            summary: "The one you can make entirely from the cupboard.",
            sourceKind: .manual,
            servings: 4,
            prepMinutes: 10,
            cookMinutes: 25,
            ingredients: [
                Ingredient(order: 0, header: "For the base:"),
                Ingredient(order: 1, rawText: "2 tbsp olive oil", quantity: 2, unit: "tbsp", name: "olive oil", groceryCategory: .pantry),
                Ingredient(order: 2, rawText: "1 onion, finely chopped", quantity: 1, unit: "piece", name: "onion", note: "finely chopped", groceryCategory: .produce),
                Ingredient(order: 3, rawText: "4 cloves garlic, crushed", quantity: 4, unit: "clove", name: "garlic", note: "crushed", groceryCategory: .produce),
                Ingredient(order: 4, rawText: "1 thumb ginger, grated", quantity: 1, unit: "piece", name: "ginger", note: "grated", groceryCategory: .produce),
                Ingredient(order: 5, header: "For the curry:"),
                Ingredient(order: 6, rawText: "2 tsp ground cumin", quantity: 2, unit: "tsp", name: "ground cumin", groceryCategory: .pantry),
                Ingredient(order: 7, rawText: "1 tsp ground turmeric", quantity: 1, unit: "tsp", name: "ground turmeric", groceryCategory: .pantry),
                Ingredient(order: 8, rawText: "1 can chopped tomatoes", quantity: 1, unit: "can", name: "chopped tomatoes", groceryCategory: .pantry),
                Ingredient(order: 9, rawText: "2 cans chickpeas, drained", quantity: 2, unit: "can", name: "chickpeas", note: "drained", groceryCategory: .pantry),
                Ingredient(order: 10, rawText: "200 ml coconut milk", quantity: 200, unit: "ml", name: "coconut milk", groceryCategory: .pantry),
                Ingredient(order: 11, rawText: "100 g spinach", quantity: 100, unit: "g", name: "spinach", groceryCategory: .produce)
            ],
            steps: [
                RecipeStep(order: 0, text: "Soften the onion in the oil over medium heat for about 8 minutes, until translucent and sweet.", durationSeconds: 480),
                RecipeStep(order: 1, text: "Add the garlic and ginger and cook for another minute, until fragrant.", durationSeconds: 60),
                RecipeStep(order: 2, text: "Stir in the spices and let them toast for 30 seconds — this is where the flavour comes from.", durationSeconds: 30),
                RecipeStep(order: 3, text: "Add the tomatoes, chickpeas and coconut milk. Simmer for 15 minutes, stirring now and then.", durationSeconds: 900),
                RecipeStep(order: 4, text: "Fold the spinach through in handfuls until it wilts. Season and serve.")
            ],
            collections: collections,
            tags: ["vegan", "storecupboard", "weeknight"],
            isFavorite: true,
            rating: 4
        )
    }

    static func roastChicken(collections: [RecipeCollection] = []) -> Recipe {
        Recipe(
            title: "Sunday Roast Chicken",
            summary: "Salt it the night before. That's the whole trick.",
            sourceName: "Mom's index card",
            sourceKind: .manual,
            servings: 4,
            prepMinutes: 15,
            cookMinutes: 80,
            ingredients: [
                Ingredient(order: 0, rawText: "1 whole chicken, about 1.6 kg", quantity: 1, unit: "piece", name: "whole chicken", note: "about 1.6 kg", groceryCategory: .meat),
                Ingredient(order: 1, rawText: "1 tbsp flaky salt", quantity: 1, unit: "tbsp", name: "flaky salt", groceryCategory: .pantry),
                Ingredient(order: 2, rawText: "1 lemon, halved", quantity: 1, unit: "piece", name: "lemon", note: "halved", groceryCategory: .produce),
                Ingredient(order: 3, rawText: "1 head garlic, halved crosswise", quantity: 1, unit: "piece", name: "garlic", note: "halved crosswise", groceryCategory: .produce),
                Ingredient(order: 4, rawText: "A few sprigs thyme", name: "thyme", note: "a few sprigs", groceryCategory: .produce),
                Ingredient(order: 5, rawText: "500 g baby potatoes", quantity: 500, unit: "g", name: "baby potatoes", groceryCategory: .produce),
                Ingredient(order: 6, rawText: "2 tbsp olive oil", quantity: 2, unit: "tbsp", name: "olive oil", groceryCategory: .pantry)
            ],
            steps: [
                RecipeStep(order: 0, text: "The night before, pat the chicken dry and salt it all over. Leave it uncovered in the fridge — this dries the skin and seasons the meat right through."),
                RecipeStep(order: 1, text: "Take the chicken out an hour before cooking and heat the oven to 220°C.", durationSeconds: 3600),
                RecipeStep(order: 2, text: "Stuff the cavity with the lemon, garlic and thyme. Toss the potatoes in oil around the bird."),
                RecipeStep(order: 3, text: "Roast at 220°C for 20 minutes, then drop to 190°C for another 50 to 60 minutes.", durationSeconds: 1200),
                RecipeStep(order: 4, text: "The chicken is done when the juices from the thigh run clear and a thermometer reads 74°C at the thickest part."),
                RecipeStep(order: 5, text: "Rest it for at least 15 minutes before carving. Don't skip this.", durationSeconds: 900)
            ],
            collections: collections,
            tags: ["roast", "sunday", "comfort"],
            isFavorite: true,
            rating: 5
        )
    }

    /// Every sample, unattached to collections — for previews.
    static var allSamples: [Recipe] {
        [bananaBread(), misoSalmon(), cacioEPepe(), chickpeaCurry(), roastChicken()]
    }

    /// A single recipe for previews that only need one.
    static var sample: Recipe { bananaBread() }
}
