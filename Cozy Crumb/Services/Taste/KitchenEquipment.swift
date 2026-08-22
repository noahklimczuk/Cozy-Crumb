//
//  KitchenEquipment.swift
//  Cozy Crumb
//
//  Which appliances a recipe asks for, read off its method.
//
//  The inference rule is one-directional and stays that way: cooking three
//  recipes that call for an air fryer means they own an air fryer; never
//  having cooked a stand-mixer recipe means nothing at all. Plenty of people
//  own a stand mixer and cook curries. Absence is not evidence here, and
//  writing "no stand mixer" into a profile on that basis would start filtering
//  out recipes for no reason.
//

import Foundation

nonisolated enum KitchenEquipment {

    /// Display name → the phrases that mean it.
    nonisolated static let markers: [String: [String]] = [
        "air fryer": ["air fryer", "air-fry", "air fry"],
        "stand mixer": ["stand mixer", "dough hook", "paddle attachment"],
        "food processor": ["food processor", "blitz in a processor"],
        "blender": ["blender", "immersion blender", "stick blender"],
        "slow cooker": ["slow cooker", "crock pot", "crockpot"],
        "pressure cooker": ["pressure cooker", "instant pot"],
        "dutch oven": ["dutch oven", "casserole dish", "heavy-based pot"],
        "cast iron pan": ["cast iron", "cast-iron"],
        "wok": ["wok"],
        "barbecue": ["barbecue", "bbq", "charcoal grill"],
        "sous vide": ["sous vide", "immersion circulator"],
        "mandoline": ["mandoline"],
        "thermometer": ["thermometer", "probe"],
        "stand blender": ["nutribullet", "vitamix"],
        "pasta machine": ["pasta machine", "pasta roller"],
        "waffle iron": ["waffle iron", "waffle maker"],
        "griddle": ["griddle pan", "griddle"],
        "steamer": ["steamer basket", "bamboo steamer"]
    ]

    /// Equipment named anywhere in a recipe's method.
    nonisolated static func mentioned(inSteps steps: [String]) -> Set<String> {
        let haystack = steps.joined(separator: " ").lowercased()
        guard !haystack.isEmpty else { return [] }

        var found: Set<String> = []
        for (equipment, phrases) in markers where phrases.contains(where: haystack.contains) {
            found.insert(equipment)
        }
        return found
    }

    nonisolated static func mentioned(in recipe: Recipe) -> Set<String> {
        mentioned(inSteps: recipe.orderedSteps.map(\.text))
    }
}
