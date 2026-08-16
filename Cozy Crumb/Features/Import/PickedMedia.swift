//
//  PickedMedia.swift
//  Cozy Crumb
//
//  Getting a video out of the Photos picker and onto disk.
//
//  `PhotosPickerItem` will hand over an image as `Data` without ceremony, but a
//  movie arrives as a file that only exists for the length of the transfer, so
//  it has to be copied somewhere we control before it can be read. The copy is
//  deleted by whoever consumes it (`ImportViewModel.importPickedVideo`).
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import os

nonisolated struct PickedMovie: Transferable {
    let url: URL

    nonisolated init(url: URL) {
        self.url = url
    }

    nonisolated static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let destination = URL.temporaryDirectory.appending(
                path: "cozy-import-\(UUID().uuidString).\(received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)"
            )

            // A picker can hand the same file over twice if the user changes
            // their mind and picks it again.
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: received.file, to: destination)

            return PickedMovie(url: destination)
        }
    }
}
