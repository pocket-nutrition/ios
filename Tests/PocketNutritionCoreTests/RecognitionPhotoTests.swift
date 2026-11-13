// SPDX-License-Identifier: MPL-2.0

import Foundation
import Testing

import PocketNutritionCore

@Suite("meal photo captures")
struct RecognitionPhotoTests {

    @Test("a .jpg file is a photo, anything else is a voice clip")
    func mediaFromExtension() {
        #expect(recognitionMediaPart(fileName: "ABC.jpg") == .photo)
        #expect(recognitionMediaPart(fileName: "ABC.JPG") == .photo)
        #expect(recognitionMediaPart(fileName: "ABC.m4a") == .voice)
        #expect(recognitionMediaPart(fileName: "no-extension") == .voice)
    }

    @Test("the photo goes in the same audio field, as image/jpeg")
    func photoPart() {
        let body = recognitionMultipartBody(boundary: "B", audio: Data([0xFF, 0xD8]), media: .photo)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("name=\"audio\"; filename=\"meal.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(!text.contains("audio/mp4"))
    }

    @Test("a photo entry remembers it is a photo after its file is released")
    func entryKind() throws {
        let photo = RecognitionEntry(localId: "p", createdAt: 0, audioFile: "X.jpg")
        let voice = RecognitionEntry(localId: "v", createdAt: 0, audioFile: "X.m4a")
        #expect(photo.isPhoto == true)
        #expect(voice.isPhoto == nil)
        #expect(photo.applying(.audioLost).isPhoto == true)

        let decoded = try StoredEntries.decode(try StoredEntries.encode([photo, voice]))
        #expect(decoded.map(\.isPhoto) == [true, nil])
    }

    @Test("photos are scaled down to the longest side, never up")
    func targetSize() throws {
        let landscape = try #require(recognitionPhotoTargetSize(width: 4032, height: 3024))
        #expect(landscape.width == 1024 && landscape.height == 768)
        let portrait = try #require(recognitionPhotoTargetSize(width: 3024, height: 4032))
        #expect(portrait.width == 768 && portrait.height == 1024)
        let small = try #require(recognitionPhotoTargetSize(width: 640, height: 480))
        #expect(small.width == 640 && small.height == 480)
        #expect(recognitionPhotoTargetSize(width: 0, height: 10) == nil)
    }
}
