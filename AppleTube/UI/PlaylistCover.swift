import SwiftUI

/// AppleTube's playlist covers. Every cover follows one template so the library reads as a set:
/// a two-tone gradient, a white motif in the upper right, a small "PLAYLIST" label with the app glyph
/// top-left, and the playlist name set large and bold in the lower left. Only the palette and motif vary,
/// and by default both come from the playlist ID, so a playlist always gets the same cover.
struct CoverStyle: Codable, Hashable {
    var palette: Int
    var motif: Motif
    /// Show YouTube's own artwork instead (for playlists that have one).
    var useOriginal = false

    enum Motif: String, Codable, CaseIterable, Identifiable {
        case rings, bars, waves, dots
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .rings: "circle.circle"
            case .bars: "chart.bar.fill"
            case .waves: "water.waves"
            case .dots: "circle.grid.3x3.fill"
            }
        }
    }

    static let palettes: [(name: String, colors: [Color])] = [
        ("Coral", [rgb(255, 94, 98), rgb(255, 160, 104)]),
        ("Ocean", [rgb(24, 90, 157), rgb(67, 206, 162)]),
        ("Grape", [rgb(103, 58, 183), rgb(236, 64, 122)]),
        ("Sunset", [rgb(255, 81, 47), rgb(221, 36, 118)]),
        ("Mint", [rgb(0, 168, 150), rgb(150, 201, 61)]),
        ("Midnight", [rgb(20, 30, 48), rgb(52, 84, 120)]),
        ("Peach", [rgb(255, 126, 125), rgb(255, 191, 150)]),
        ("Sky", [rgb(47, 128, 237), rgb(86, 204, 242)]),
        ("Ember", [rgb(120, 20, 40), rgb(240, 72, 50)]),
        ("Lavender", [rgb(150, 100, 245), rgb(250, 113, 205)]),
        ("Forest", [rgb(17, 75, 60), rgb(70, 160, 100)]),
        ("Graphite", [rgb(30, 30, 36), rgb(84, 84, 96)]),
    ]

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255) }

    /// Stable per playlist (Swift's hashValue changes every launch, so use FNV-1a).
    static func `default`(for id: String) -> CoverStyle {
        let hash = id.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        if id == LikedMusicPlaylist.id { return CoverStyle(palette: 2, motif: .rings) }
        return CoverStyle(palette: Int(hash % UInt64(palettes.count)), motif: Motif.allCases[Int((hash >> 8) % 4)])
    }

    var colors: [Color] { Self.palettes[palette % Self.palettes.count].colors }
}

struct CoverEditRequest: Identifiable {
    var id: String { playlistId }
    let playlistId: String
    let title: String
}

/// Saved cover choices (on this device) and which playlists get a generated cover.
@MainActor
@Observable
final class CoverStore {
    static let shared = CoverStore()

    private(set) var styles: [String: CoverStyle] = [:]
    var editing: CoverEditRequest?
    /// YouTube's artwork for playlists seen this session, so Edit Cover can offer "Use Original Artwork".
    var originalArtwork: [String: URL] = [:]
    private let key = "playlistCoverStyles"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([String: CoverStyle].self, from: data) {
            styles = saved
        }
    }

    func style(for id: String) -> CoverStyle { styles[YTMusicAPI.bareId(id)] ?? .default(for: YTMusicAPI.bareId(id)) }

    func setStyle(_ style: CoverStyle, for id: String) {
        styles[YTMusicAPI.bareId(id)] = style
        UserDefaults.standard.set(try? JSONEncoder().encode(styles), forKey: key)
    }

    /// Your playlists, Liked Songs, and anything without artwork get the generated cover, unless you chose the
    /// original. Other playlists use their artwork unless you designed a cover for them.
    func usesGeneratedCover(id: String, hasArtwork: Bool) -> Bool {
        let bare = YTMusicAPI.bareId(id)
        if let chosen = styles[bare] { return !chosen.useOriginal || !hasArtwork }
        return !hasArtwork || bare == LikedMusicPlaylist.id || LibraryState.shared.isOwned(bare)
    }
}

/// The generated cover itself; scales with its width.
struct GeneratedCover: View {
    let title: String
    let style: CoverStyle
    var cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                MotifShape(motif: style.motif)
                    .fill(.white.opacity(0.22))
                    .frame(width: w * 0.62, height: w * 0.62)
                    .offset(x: w * 0.44, y: -w * 0.06)
                HStack(spacing: w * 0.025) {
                    Image(systemName: title == "Liked Songs" ? "heart.fill" : "music.note.list")
                    Text("PLAYLIST").kerning(w * 0.008)
                }
                .font(.system(size: max(w * 0.055, 6), weight: .heavy))
                .foregroundStyle(.white.opacity(0.85))
                .padding(w * 0.07)
                Text(title)
                    .font(.system(size: w * 0.13, weight: .heavy))
                    .lineSpacing(-w * 0.02)
                    .minimumScaleFactor(0.45)
                    .lineLimit(3)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: w * 0.01, y: w * 0.005)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(w * 0.07)
            }
            .frame(width: w, height: w)
            .clipped()
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("\(title) cover")
    }
}

/// The four motifs, drawn in a unit square and scaled by the frame.
struct MotifShape: Shape {
    let motif: CoverStyle.Motif

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        switch motif {
        case .rings:
            for i in 0 ..< 4 {
                let outer = s / 2 * (1 - CGFloat(i) * 0.24), inner = outer - s * 0.07
                path.addEllipse(in: CGRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
                path.addEllipse(in: CGRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
            }
            return path.normalized(eoFill: true)
        case .bars:
            let heights: [CGFloat] = [0.45, 0.8, 1, 0.65, 0.9, 0.5]
            let bar = s / CGFloat(heights.count * 2 - 1)
            for (i, h) in heights.enumerated() {
                let height = s * h
                path.addRoundedRect(in: CGRect(x: rect.minX + CGFloat(i) * bar * 2, y: c.y - height / 2, width: bar, height: height),
                                    cornerSize: CGSize(width: bar / 2, height: bar / 2))
            }
        case .waves:
            for i in 0 ..< 4 {
                let y0 = rect.minY + s * (0.2 + CGFloat(i) * 0.2)
                var line = Path()
                line.move(to: CGPoint(x: rect.minX, y: y0))
                for step in 1 ... 40 {
                    let x = rect.minX + s * CGFloat(step) / 40
                    line.addLine(to: CGPoint(x: x, y: y0 + sin(CGFloat(step) / 40 * .pi * 3) * s * 0.06))
                }
                path.addPath(line.strokedPath(StrokeStyle(lineWidth: s * 0.045, lineCap: .round)))
            }
        case .dots:
            let n = 5
            let step = s / CGFloat(n)
            for row in 0 ..< n {
                for col in 0 ..< n {
                    let r = step * (0.18 + 0.12 * CGFloat((row + col) % 3))
                    path.addEllipse(in: CGRect(x: rect.minX + step * (CGFloat(col) + 0.5) - r, y: rect.minY + step * (CGFloat(row) + 0.5) - r,
                                               width: r * 2, height: r * 2))
                }
            }
        }
        return path
    }
}

/// Use this wherever a playlist's artwork is shown: picks the generated cover or YouTube's artwork.
struct PlaylistArtwork: View {
    let id: String
    let title: String
    let url: URL?
    var cornerRadius: CGFloat = 8
    var pixelSize = 544
    @State private var covers = CoverStore.shared

    var body: some View {
        if covers.usesGeneratedCover(id: id, hasArtwork: url != nil) {
            GeneratedCover(title: title, style: covers.style(for: id), cornerRadius: cornerRadius)
        } else {
            ArtworkView(url: url, cornerRadius: cornerRadius, pixelSize: pixelSize)
        }
    }
}

/// "Edit Cover": live preview, palette swatches, motif choice, and (when there is one) the original artwork.
struct EditCoverView: View {
    let request: CoverEditRequest
    var originalArtwork: URL?
    @State private var style: CoverStyle
    @Environment(\.dismiss) private var dismiss

    init(request: CoverEditRequest, originalArtwork: URL? = nil) {
        self.request = request
        self.originalArtwork = originalArtwork
        let store = CoverStore.shared
        var initial = store.style(for: request.playlistId)
        initial.useOriginal = initial.useOriginal || !store.usesGeneratedCover(id: request.playlistId, hasArtwork: originalArtwork != nil)
        _style = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Group {
                        if style.useOriginal, let originalArtwork {
                            ArtworkView(url: originalArtwork, cornerRadius: 14)
                        } else {
                            GeneratedCover(title: request.title, style: style, cornerRadius: 14)
                        }
                    }
                    .frame(width: 260)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
                    .animation(.spring(duration: 0.35), value: style)

                    if originalArtwork != nil {
                        Toggle("Use Original Artwork", isOn: $style.useOriginal).padding(.horizontal)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Colour").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                            ForEach(CoverStyle.palettes.indices, id: \.self) { index in
                                Button {
                                    style.palette = index
                                    style.useOriginal = false
                                } label: {
                                    Circle()
                                        .fill(LinearGradient(colors: CoverStyle.palettes[index].colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(height: 44)
                                        .overlay(Circle().strokeBorder(.primary, lineWidth: style.palette == index && !style.useOriginal ? 3 : 0).padding(-4))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(CoverStyle.palettes[index].name)
                            }
                        }

                        Text("Pattern").font(.headline).padding(.top, 8)
                        Picker("Pattern", selection: Binding(get: { style.motif }, set: { style.motif = $0; style.useOriginal = false })) {
                            ForEach(CoverStyle.Motif.allCases) { motif in
                                Image(systemName: motif.symbol).tag(motif).accessibilityLabel(motif.rawValue.capitalized)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button("Surprise Me", systemImage: "dice") {
                            style.palette = Int.random(in: 0 ..< CoverStyle.palettes.count)
                            style.motif = CoverStyle.Motif.allCases.randomElement() ?? .rings
                            style.useOriginal = false
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 24)
            }
            .navigationTitle("Edit Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        CoverStore.shared.setStyle(style, for: request.playlistId)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
