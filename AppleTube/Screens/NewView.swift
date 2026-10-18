import SwiftUI

/// Apple Music "New": YouTube Music's Explore feed (new releases, charts, moods) as shelves.
struct NewView: View {
    @State private var sections: Loadable<[HomeSection]> = .loading

    var body: some View {
        NavigationStack {
            ScrollView {
                switch sections {
                case .loading:
                    LoadingView()
                case let .failed(message):
                    ErrorView(message: message) { Task { await load() } }
                case let .loaded(sections):
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(sections) { section in
                            Shelf(title: section.title) {
                                ForEach(section.items) { ItemCard(item: $0) }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("New")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { AccountButton() } }
            .musicDestinations()
            .refreshable { await load() }
            .task { if case .loading = sections { await load() } }
        }
    }

    private func load() async {
        do {
            // Explore's first shelf is navigation buttons (New releases, Charts, Moods) with no artwork; skip those.
            let sections = try await YTMusicAPI.shared.explore()
                .map { HomeSection(id: $0.id, title: $0.title, items: $0.items.filter { $0.thumbnailURL != nil }, isChart: $0.isChart) }
                .filter { !$0.items.isEmpty }
            self.sections = sections.isEmpty ? .failed("Nothing new to show right now.") : .loaded(sections)
        } catch {
            sections = .failed(error.localizedDescription)
        }
    }
}
