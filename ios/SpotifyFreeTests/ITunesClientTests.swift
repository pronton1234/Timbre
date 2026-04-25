import XCTest
@testable import SpotifyFree

final class ITunesClientTests: XCTestCase {

    func testArtworkUpscalingReplacesSize() {
        let url = URL(string: "https://is1-ssl.mzstatic.com/image/thumb/Music/abc/100x100bb.jpg")!
        let big = iTunesClient.upscaleArtwork(url)
        XCTAssertEqual(big?.absoluteString.contains("600x600bb"), true)
    }

    func testArtworkUpscalingHandlesNil() {
        XCTAssertNil(iTunesClient.upscaleArtwork(nil))
    }

    func testMapTrackFillsAllFields() {
        let item = ITunesItem(
            wrapperType: "track", kind: "song",
            trackId: 1234, trackName: "Blinding Lights",
            artistId: 5678, artistName: "The Weeknd",
            collectionId: 4321, collectionName: "After Hours",
            trackTimeMillis: 200040,
            artworkUrl100: "https://is1-ssl.mzstatic.com/foo/100x100bb.jpg",
            previewUrl: "https://example.com/preview.m4a",
            isrc: "USUG12001534", releaseDate: nil, trackCount: nil,
            primaryGenreName: nil, artistLinkUrl: nil
        )
        let t = iTunesClient.mapTrack(item)
        XCTAssertEqual(t?.itunesTrackId, 1234)
        XCTAssertEqual(t?.isrc, "USUG12001534")
        XCTAssertEqual(t?.durationMs, 200040)
        XCTAssertEqual(t?.artworkUrl?.absoluteString.contains("600x600bb"), true)
    }

    func testMapTrackReturnsNilWithoutRequiredFields() {
        let item = ITunesItem(
            wrapperType: nil, kind: nil, trackId: nil, trackName: nil, artistId: nil,
            artistName: nil, collectionId: nil, collectionName: nil, trackTimeMillis: nil,
            artworkUrl100: nil, previewUrl: nil, isrc: nil, releaseDate: nil,
            trackCount: nil, primaryGenreName: nil, artistLinkUrl: nil
        )
        XCTAssertNil(iTunesClient.mapTrack(item))
    }
}
