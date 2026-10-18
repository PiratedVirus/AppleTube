# AppleTube

Personal iOS app: Apple Music-style UI on top of the user's YouTube Music Premium account. Sideloaded via Xcode to one iPhone only; never distributed.

## Rules
- Backend is YouTube Music only (InnerTube API + hidden WKWebView player, Kaset-style). No Apple Music APIs.
- Never handle the user's Google password; the user logs in themselves inside the WKWebView.
- `reference/` holds cloned repos (kaset = MIT, SwiftyTube = GPL-3.0). It is gitignored. Copied Kaset code must keep its MIT notice.
- Match Apple Music visually using the user's own reference screenshots in `docs/reference-screens/`.

## Build
- `xcodegen generate` after changing `project.yml` (the .xcodeproj is generated, not committed).
- Simulator: `xcodebuild -project AppleTube.xcodeproj -scheme AppleTube -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Device: set DEVELOPMENT_TEAM in project.yml, then `-destination 'platform=iOS,name=<iPhone name>'`.

## Stages
0 setup · 1 read references · 2 playback spike (lock-screen background audio is the go/no-go) · 3 map API with REA · 4 UI screen by screen · 5 device + polish
