//
//  CookLog.swift
//  Cozy Crumb
//
//  The "I made this" history — one entry per cook, with an optional rating,
//  note and photo.
//

import Foundation
import SwiftData

@Model
final class CookLog {
    @Attribute(.unique) var id: UUID
    var date: Date
    /// 1–5.
    var rating: Int?
    var notes: String?

    @Attribute(.externalStorage) var photoData: Data?

    var recipe: Recipe?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        rating: Int? = nil,
        notes: String? = nil,
        photoData: Data? = nil
    ) {
        self.id = id
        self.date = date
        self.rating = rating
        self.notes = notes
        self.photoData = photoData
    }
}
