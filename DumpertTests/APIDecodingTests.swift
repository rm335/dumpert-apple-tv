import Testing
import Foundation
@testable import Dumpert

private class BundleToken {}

private enum FixtureError: Error {
    case notFound(String)
}

@Suite("API Decoding Tests")
struct APIDecodingTests {
    private let decoder = JSONDecoder()

    private func loadFixture(_ name: String) throws -> Data {
        guard let url = Bundle(for: BundleToken.self).url(
            forResource: name, withExtension: "json", subdirectory: "Fixtures"
        ) else {
            throw FixtureError.notFound(name)
        }
        return try Data(contentsOf: url)
    }

    @Test("Decode hotshiz response")
    func decodeHotshiz() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)

        #expect(response.gentime != nil)
        #expect(response.items != nil)
        #expect(!response.items!.isEmpty)

        let item = response.items!.first!
        #expect(!item.id.isEmpty)
        #expect(!item.title.isEmpty)
        #expect(item.media != nil)
        #expect(!item.media!.isEmpty)
        #expect(item.stats != nil)
        #expect(item.stats!.kudosTotal != nil)
    }

    @Test("Decode latest response")
    func decodeLatest() throws {
        let data = try loadFixture("latest")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)

        #expect(response.items != nil)
        #expect(!response.items!.isEmpty)
    }

    @Test("Decode search response")
    func decodeSearch() throws {
        let data = try loadFixture("search_reeten")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)

        #expect(response.items != nil)
        #expect(!response.items!.isEmpty)
    }

    @Test("Convert DumpertItem to Video")
    func convertToVideo() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let video = Video(from: item)

        #expect(video.id == item.id)
        #expect(video.title == item.title)
        #expect(!video.descriptionText.contains("<"))  // HTML stripped
        #expect(video.thumbnailURL != nil)
        #expect(video.streamURL != nil)
    }

    @Test("HLS stream URL preferred")
    func hlsStreamPreferred() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let video = Video(from: item)

        // Stream URL should be an HLS manifest
        if let streamURL = video.streamURL {
            #expect(streamURL.pathExtension == "m3u8")
        }
    }

    @Test("Tags parsed as space-separated")
    func tagsParsed() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let video = Video(from: item)

        if let tags = item.tags, !tags.isEmpty {
            #expect(!video.tags.isEmpty)
            for tag in video.tags {
                #expect(!tag.contains(" "))
                #expect(!tag.isEmpty)
            }
        }
    }

    @Test("Media variants decoded with stream version")
    func mediaVariants() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let variants = item.media!.first!.variants!

        let versions = Set(variants.map(\.version))
        #expect(versions.contains("stream"))
        #expect(versions.contains("720p"))
    }

    @Test("Stills dictionary decoded with still-large")
    func stillsDecoded() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!

        #expect(item.stills != nil)
        #expect(item.stills?["still-large"] != nil)
    }

    @Test("Thumbnail prefers still-large from stills dict")
    func thumbnailPrefersStillLarge() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let video = Video(from: item)

        if let stillLarge = item.stills?["still-large"] {
            #expect(video.thumbnailURL?.absoluteString == stillLarge)
        }
    }

    // MARK: - MediaItem & Photo Tests

    @Test("MediaItem creates video for VIDEO type")
    func mediaItemVideo() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let mediaItem = MediaItem(from: item)

        #expect(mediaItem.isVideo)
        #expect(!mediaItem.isPhoto)
        #expect(mediaItem.id == item.id)
        #expect(mediaItem.title == item.title)
    }

    @Test("MediaItem creates photo for FOTO type")
    func mediaItemPhoto() throws {
        let data = try loadFixture("foto_item")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!

        #expect(item.mediaType == "FOTO")

        let mediaItem = MediaItem(from: item)

        #expect(mediaItem.isPhoto)
        #expect(!mediaItem.isVideo)
        #expect(mediaItem.id == item.id)
        #expect(mediaItem.duration == 0)
    }

    @Test("Photo has imageURL from foto variant")
    func photoImageURL() throws {
        let data = try loadFixture("foto_item")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let photo = Photo(from: item)

        #expect(photo.imageURL != nil)
        #expect(photo.thumbnailURL != nil)
        #expect(photo.imageURL?.absoluteString.contains("image.jpg") == true)
    }

    // MARK: - Views (stats) mapping

    @Test("Video carries viewsTotal from stats")
    func videoViewsTotal() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let video = Video(from: item)

        #expect(video.viewsTotal == item.stats?.viewsTotal)
        #expect(video.viewsTotal == 63759)
    }

    @Test("Photo carries viewsTotal from stats")
    func photoViewsTotal() throws {
        let data = try loadFixture("foto_item")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let photo = Photo(from: item)

        #expect(photo.viewsTotal == 4793)
    }

    @Test("MediaItem exposes viewsTotal")
    func mediaItemViewsTotal() throws {
        let data = try loadFixture("hotshiz")
        let response = try decoder.decode(DumpertAPIResponse.self, from: data)
        let item = response.items!.first!
        let mediaItem = MediaItem(from: item)

        #expect(mediaItem.viewsTotal == 63759)
    }

    // MARK: - Endpoint URLs

    @Test("topDay endpoint builds the /top5/dag path")
    func topDayEndpointURL() throws {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 6
        comps.day = 2
        let date = try #require(Calendar.current.date(from: comps))

        let url = APIEndpoint.topDay(date: date).url
        #expect(url.absoluteString == "https://post.dumpert.nl/api/v1.0/top5/dag/2026-06-02")
    }
}
