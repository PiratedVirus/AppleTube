import SwiftUI

/// Account sheet behind the profile button: sign in/out of YouTube Music, plus the playback diagnostics.
struct AccountView: View {
    @State private var app = AppState.shared
    @State private var showLogin = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("YouTube Music", value: app.signedIn == true ? "Signed In" : "Signed Out")
                    if app.signedIn == true {
                        Button("Sign Out", role: .destructive) {
                            Task {
                                await WebSession.signOut()
                                await app.refreshSignIn()
                            }
                        }
                    } else {
                        Button("Sign In to YouTube Music") { showLogin = true }
                    }
                } footer: {
                    Text("Sign in with the Google account that has YouTube Music Premium. AppleTube never sees your password.")
                }

                Section("Diagnostics") {
                    NavigationLink("Playback Test") { PlaybackSpikeView() }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Done") { dismiss() } }
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
        }
    }
}
