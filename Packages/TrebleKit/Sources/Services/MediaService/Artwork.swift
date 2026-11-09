import AppKit
import ImageIO

/// Fetches and downsizes album art. Only the current track's art is kept, in memory.
enum Artwork {
    /// No disk cache, no cookies: nothing about your listening is stored.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    static func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Spotify's public oEmbed endpoint gives a 300px cover without needing
    /// permission to control Spotify. Used until (or unless) that's allowed.
    static func spotifyPublicArtworkURL(for trackID: String) async -> URL? {
        guard let page = NowPlayingLogic.spotifyPageURL(for: trackID),
              var components = URLComponents(string: "https://open.spotify.com/oembed") else { return nil }
        components.queryItems = [URLQueryItem(name: "url", value: page.absoluteString)]
        guard let url = components.url, let data = await download(url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let thumbnail = json["thumbnail_url"] as? String else { return nil }
        return URL(string: thumbnail)
    }

    /// Decodes and shrinks an image to at most `maxPixels` on its longest side,
    /// so a big cover never sits in memory at full size.
    @MainActor
    static func image(from data: Data, maxPixels: Int = 600) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width / 2, height: cgImage.height / 2))
    }
}
