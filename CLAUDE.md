# AppleTube

Personal iOS app: Apple Music-style UI on top of the user's YouTube Music Premium account. Sideloaded via Xcode to one iPhone only; never distributed.

## Rules
- Backend is YouTube Music only (InnerTube API + hidden WKWebView player, Kaset-style). No Apple Music APIs.
- Never handle the user's Google password; the user logs in themselves inside the WKWebView.
- `reference/` holds cloned repos (kaset = MIT, SwiftyTube = GPL-3.0). It is gitignored. Copied Kaset code must keep its MIT notice.
- Match Apple Music visually using the user's own reference screenshots in `docs/reference-screens/`.

## Build
- `xcodegen generate` after changing `project.yml` (the .xcodeproj is generated, not committed).
- Simulator: `xcodebuild -project AppleTube.xcodeproj -scheme AppleTube -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0' -derivedDataPath build build`. Use the iOS 27.0 iPhone 18 Pro sim: the iOS 27.1 runtime only supports the foldable "iPhone Duo", which renders the wide layout.
- Device: signing team + bundle ID in `Local.yml` (gitignored, from Local.example.yml), then `-destination 'platform=iOS,name=<iPhone name>'`.

## Testing
- `xcodebuild test ... -scheme AppleTube` runs parser tests against `AppleTubeTests/Fixtures` (real signed-out responses).
- Refresh fixtures when YouTube changes: `python3 -I Scripts/capture_fixtures.py AppleTubeTests/Fixtures`.
- Screenshots: `Scripts/screenshot.sh <out.png> <wait> [args]`. Launch args: `-startTab radio|library|search`,
  `-openRoute playlist:<id>|artist:<id>`, `-autoplayVideoId <id>`, `-showNowPlaying YES`, `-nowPlayingPanel lyrics|queue`,
  `-searchQuery <text>`, `-thenPlayVideoId <id>` (switch track after 30s). First launch after install takes ~15s; wait longer for the first shot.
- Device: the user's iPhone 15, iOS 27 (found automatically; override with APPLETUBE_DEVICE). Install with `Scripts/refresh_install.sh --force` (builds HEAD, installs over Wi-Fi,
  records the profile expiry). A launchd agent (`Scripts/install_refresh_agent.sh`) runs it hourly and reinstalls
  within 3 days of the free 7-day profile expiring; log in `~/Library/Logs/AppleTubeRefresh.log`. Needs the Apple ID
  signed in under Xcode → Settings → Accounts to renew profiles.
  Crash logs: `xcrun devicectl device info files --domain-type systemCrashLogs`.

## Gotchas
- Closures MediaPlayer/WebKit call off-main must not be main-actor isolated (Swift 6 traps); build them in `nonisolated` helpers.
- Lock Screen controls come from the page's Media Session handlers (WebKit), not MPRemoteCommandCenter.
- YouTube Music's web app ignores queue commands passed to `resolveCommand` (play next, add, remove). The working
  path is clicking the real queue-row menu item, retargeting `queueTarget.videoId` (see WebPlayer+Queue.swift).
  Jump to a queue row by clicking its `ytmusic-play-button-renderer`. Shuffle/repeat are player-bar buttons; autoplay is `#automix`.
- In a List, NavigationLink renders as a full-width chevron row; use a Button + navigationDestination(item:) inside headers.
- A List row containing several NavigationLinks fires all of them on one tap (pushed a stack of playlists). Put grids
  and shelves in a ScrollView, never in a List row.
- Don't use zoom navigation transitions for pushes: they disable the edge swipe-back.
- The hidden player web view must stay `accessibilityElementsHidden`, or VoiceOver and UI tests see the whole YT page.
- `.task(id:)` re-runs when a view reappears (e.g. after Back); guard against resetting state.
- UI tests: `xcodebuild test ... -only-testing:AppleTubeUITests` (live network; ~2 min).

## Stages
0 setup · 1 read references · 2 playback spike (lock-screen background audio is the go/no-go) · 3 map API with REA · 4 UI screen by screen · 5 device + polish
