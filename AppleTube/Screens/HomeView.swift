import SwiftUI

/// Apple Music "Home": large "Top Picks" cards first, then titled shelves.
/// Content is YouTube Music's home feed (Quick picks, mixes, recommendations).
struct HomeView: View {
    @State private var sections: Loadable<[HomeSection]> = .loading
    @State private var continuation: String?
    @State private var isLoadingMore = false
    @State private var app = AppState.shared

    var body: some View {
        NavigationStack(path: $app.homePath) {
            ScrollView {
                switch sections {
                case .loading:
                    LoadingView()
                case let .failed(message):
                    ErrorView(message: message) { Task { await load() } }
                case let .loaded(sections):
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            if index == 0 {
                                TopPicksShelf(section: section)
                            } else {
                                Shelf(title: section.title) {
                                    ForEach(section.items) { ItemCard(item: $0) }
                                }
                            }
                        }
                        if continuation != nil {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Home")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AccountButton() } }
            .musicDestinations()
            .refreshable { await load() }
            .task {
                // `-openRoute playlist:<id>` or `artist:<id>` opens a page on launch (screenshots/testing).
                if app.homePath.isEmpty, let raw = UserDefaults.standard.string(forKey: "openRoute") {
                    let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        app.homePath.append(parts[0] == "artist" ? Route.artist(id: parts[1], name: "") : Route.playlist(id: parts[1], title: ""))
                    }
                }
                if case .loading = sections { await load() }
            }
            .onChange(of: AppState.shared.signedIn) { _, _ in Task { await load() } }
        }
    }

    private func load() async {
        do {
            let page = try await YTMusicAPI.shared.home()
            sections = .loaded(page.response.sections.filter { !$0.items.isEmpty })
            continuation = page.continuation
        } catch {
            sections = .failed(error.localizedDescription)
        }
    }

    private func loadMore() async {
        guard let token = continuation, !isLoadingMore, case let .loaded(current) = sections else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await YTMusicAPI.shared.homeContinuation(token) else {
            continuation = nil
            return
        }
        let known = Set(current.map(\.id))
        sections = .loaded(current + page.sections.filter { !$0.items.isEmpty && !known.contains($0.id) })
        continuation = page.continuation
    }
}

/// The first Home shelf as big Apple Music-style cards: artwork on top, a tinted caption panel below.
private struct TopPicksShelf: View {
    let section: HomeSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title).font(.title2.bold()).padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(section.items) { TopPickCard(item: $0) }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
        }
    }
}

private struct TopPickCard: View {
    let item: HomeSectionItem
    @State private var tint: Color = .gray

    var body: some View {
        Group {
            if let route = item.route {
                NavigationLink(value: route) { card }
            } else {
                Button {
                    if let id = item.videoId { WebPlayer.shared.play(videoId: id, playlistId: nil) }
                } label: { card }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { ItemMenu(item: item) }
        .task { tint = await ArtworkColor.color(for: item.thumbnailURL) ?? .gray }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtworkView(url: item.thumbnailURL, cornerRadius: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline).lineLimit(2)
                if let subtitle = item.homeCardSubtitle {
                    Text(subtitle).font(.subheadline).opacity(0.8).lineLimit(2)
                }
            }
            .foregroundStyle(tint.prefersLightText ? .white : .black)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(12)
            .background(tint)
        }
        .frame(width: 250)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }
}
