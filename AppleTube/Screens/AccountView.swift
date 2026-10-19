import PhotosUI
import SwiftUI

/// Account & Settings, behind the profile button: who you are, how the app looks, what Home and Library show,
/// playback, and storage.
struct AccountView: View {
    @State private var app = AppState.shared
    @State private var settings = AppSettings.shared
    @State private var showLogin = false
    @State private var photoItem: PhotosPickerItem?
    @State private var confirmSignOut = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                profile
                appearance
                Section {
                    NavigationLink { HomeCustomizer() } label: {
                        Label("Customize Home", systemImage: "house")
                    }
                    Toggle(isOn: $settings.largeTopPicks) {
                        Label("Large Cards for First Shelf", systemImage: "rectangle.grid.1x2")
                    }
                    NavigationLink { LibraryCategoriesEditor(inSheet: false) } label: {
                        Label("Library Categories", systemImage: "music.note.square.stack")
                    }
                } header: {
                    Text("Home & Library")
                } footer: {
                    Text("Reorder or hide Home shelves and Library rows.")
                }

                Section("Playlist Covers") {
                    Toggle(isOn: $settings.generatedCovers) {
                        Label("Designed Covers for My Playlists", systemImage: "paintpalette")
                    }
                }

                Section {
                    Toggle(isOn: $settings.resumeAfterLock) {
                        Label("Keep Playing When Locked", systemImage: "lock.iphone")
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("Resumes music if YouTube's player pauses when the phone locks.")
                }

                storage

                Section("Diagnostics") {
                    NavigationLink("Playback Test") { PlaybackSpikeView() }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() }.bold() }
            .sheet(isPresented: $showLogin) {
                NavigationStack {
                    LoginView {
                        showLogin = false
                        Task { await app.refreshSignIn() }
                    }
                    .navigationTitle("Sign In")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("Cancel") { showLogin = false } }
                }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
                    // Store a small square-ish JPEG; the avatar is never shown larger than ~80pt.
                    let side: CGFloat = 400
                    let scale = side / min(image.size.width, image.size.height)
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    let resized = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                    settings.customProfilePhoto = resized.jpegData(compressionQuality: 0.85)
                }
            }
        }
        .tint(settings.accent.color)
    }

    private var profile: some View {
        Section {
            HStack(spacing: 16) {
                ProfileAvatar(size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.account?.name ?? (app.signedIn == true ? "YouTube Music" : "Not Signed In"))
                        .font(.title3.bold())
                    Text(app.signedIn == true ? "Signed in to YouTube Music" : "Sign in to see your library")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 6)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(settings.customProfilePhoto == nil ? "Choose Profile Photo…" : "Change Profile Photo…", systemImage: "photo")
            }
            if settings.customProfilePhoto != nil {
                Button(app.account?.photoURL == nil ? "Remove Photo" : "Use Google Photo", systemImage: "arrow.uturn.backward") {
                    settings.customProfilePhoto = nil
                }
            }
            if app.signedIn == true {
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmSignOut = true }
                    .confirmationDialog("Sign out of YouTube Music?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                        Button("Sign Out", role: .destructive) {
                            Task {
                                await WebSession.signOut()
                                await app.refreshSignIn()
                            }
                        }
                    }
            } else {
                Button("Sign In to YouTube Music", systemImage: "person.crop.circle.badge.plus") { showLogin = true }
            }
        } footer: {
            if app.signedIn != true {
                Text("Sign in with the Google account that has YouTube Music Premium. AppleTube never sees your password.")
            } else if app.account?.photoURL == nil, settings.customProfilePhoto == nil {
                Text("Your Google photo couldn't be loaded, so choose one to show in the corner.")
            }
        }
    }

    private var appearance: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Accent Colour", systemImage: "paintbrush")
                HStack(spacing: 0) {
                    ForEach(AppSettings.Accent.allCases) { accent in
                        Button {
                            withAnimation(.spring(duration: 0.3)) { settings.accent = accent }
                        } label: {
                            Circle()
                                .fill(accent.color)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().strokeBorder(.primary, lineWidth: settings.accent == accent ? 2.5 : 0).padding(-4))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(accent.rawValue.capitalized)
                        .accessibilityAddTraits(settings.accent == accent ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            }
            Picker(selection: $settings.theme) {
                Text("System").tag(AppSettings.Theme.system)
                Text("Light").tag(AppSettings.Theme.light)
                Text("Dark").tag(AppSettings.Theme.dark)
            } label: {
                Label("Theme", systemImage: "circle.lefthalf.filled")
            }
        }
    }

    private var storage: some View {
        Section {
            Button("Clear Cached Pages & Artwork", systemImage: "internaldrive") {
                YTMusicAPI.shared.clearCache()
                ImageCache.shared.clear()
                app.toast("Cache cleared", symbol: "checkmark")
            }
            Button("Clear Listening History", systemImage: "clock.arrow.circlepath") {
                PlaybackHistory.shared.clear()
                app.toast("History cleared", symbol: "checkmark")
            }
            Button("Clear Recent Searches", systemImage: "magnifyingglass") {
                RecentSearches.shared.clear()
                app.toast("Recent searches cleared", symbol: "checkmark")
            }
        } header: {
            Text("Storage")
        } footer: {
            Text("Cached pages make the app open instantly; they refresh automatically.")
        }
    }
}

/// Reorder and hide Home's shelves. Shelves are remembered by title as YouTube shows them.
struct HomeCustomizer: View {
    @State private var settings = AppSettings.shared
    @State private var order: [String] = []

    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { title in
                    Button {
                        if settings.hiddenHomeSections.contains(title) {
                            settings.hiddenHomeSections.remove(title)
                        } else {
                            settings.hiddenHomeSections.insert(title)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: settings.hiddenHomeSections.contains(title) ? "circle" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(settings.hiddenHomeSections.contains(title) ? .secondary : Color.musicAccent)
                                .contentTransition(.symbolEffect(.replace))
                            Text(title).foregroundStyle(Color(uiColor: .label))
                        }
                    }
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                    settings.homeOrder = order
                }
            } footer: {
                Text(order.isEmpty
                     ? "Open Home once and its shelves will appear here."
                     : "Untick shelves to hide them; drag to reorder. New shelves YouTube adds appear after these.")
            }
            if !settings.homeOrder.isEmpty || !settings.hiddenHomeSections.isEmpty {
                Section {
                    Button("Reset to YouTube's Order", role: .destructive) {
                        settings.homeOrder = []
                        settings.hiddenHomeSections = []
                        order = settings.knownHomeSections
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Customize Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let known = settings.knownHomeSections
            order = settings.homeOrder.filter(known.contains) + known.filter { !settings.homeOrder.contains($0) }
        }
    }
}
