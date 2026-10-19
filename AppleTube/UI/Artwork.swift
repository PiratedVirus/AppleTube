import CoreImage
import SwiftUI
import UIKit


extension URL {
    /// YouTube artwork URLs carry their size (`=w120-h120…` on googleusercontent/ggpht); ask for a sharper one.
    func artwork(size: Int) -> URL {
        let string = absoluteString
        guard string.contains("googleusercontent.com") || string.contains("ggpht.com"),
              let range = string.range(of: #"=w\d+-h\d+"#, options: .regularExpression)
        else { return self }
        return URL(string: string.replacingCharacters(in: range, with: "=w\(size)-h\(size)")) ?? self
    }
}

/// Square (or round, for artists) artwork with Apple Music's soft placeholder.
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    var isCircle = false
    var pixelSize = 544

    var body: some View {
        Color.secondary.opacity(0.15)
            .overlay {
                CachedImage(url: url?.artwork(size: pixelSize)) {
                    Image(systemName: "music.note")
                        .font(.title)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
            .overlay {
                if !isCircle {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
    }
}

/// Average colour of an artwork, used to tint album/playlist pages and Now Playing like iOS 26.4.
@MainActor
enum ArtworkColor {
    private static var cache: [URL: Color] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func color(for url: URL?) async -> Color? {
        guard let url else { return nil }
        if let cached = cache[url] { return cached }
        guard let uiImage = await ImageCache.shared.image(for: url.artwork(size: 120)),
              let image = CIImage(image: uiImage),
              let rgb = average(of: image)
        else { return nil }
        let color = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
        cache[url] = color
        return color
    }

    private static func average(of image: CIImage) -> (Double, Double, Double)? {
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255, Double(pixel[2]) / 255)
    }
}

extension Color {
    /// Whether white text reads better than black on this colour.
    var prefersLightText: Bool {
        let resolved = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 0.6
    }
}

/// Decoded artwork kept in memory (and raw bytes on disk via URLCache), so images that were seen once appear
/// immediately instead of flashing a placeholder. Decoding happens off the main thread.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 512 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    init() { memory.totalCostLimit = 120 << 20 }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func clear() {
        memory.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    func image(for url: URL) async -> UIImage? {
        if let hit = cached(url) { return hit }
        guard let (data, _) = try? await session.data(from: url),
              let image = await Task.detached(priority: .userInitiated, operation: { UIImage(data: data)?.preparingForDisplay() }).value
        else { return nil }
        memory.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4))
        return image
    }
}

struct CachedImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        // A memory hit renders synchronously on the first frame: no placeholder flash.
        if let url, let image = loaded?.url == url ? loaded?.image : ImageCache.shared.cached(url) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            placeholder
                .task(id: url) {
                    guard let url, let image = await ImageCache.shared.image(for: url) else { return }
                    withAnimation(.easeOut(duration: 0.2)) { loaded = (url, image) }
                }
        }
    }
}
