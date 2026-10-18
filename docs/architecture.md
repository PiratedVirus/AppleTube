# AppleTube architecture (Stage 1 findings)

Read from `reference/kaset` (MIT, last commit 2026-10-12) and `reference/SwiftyTube` (GPL-3.0, last commit 2026-10-15).

## How Kaset works (macOS)

### Auth
- User signs in on music.youtube.com inside a `WKWebView` (`Views/LoginWebView.swift`) using the persistent `WKWebsiteDataStore.default()`.
- Login is detected by the presence of the `SAPISID` cookie (`Views/LoginSheet.swift:462`).
- Web views use a **desktop Safari user agent** (`WebKitManager.userAgent`), so YouTube serves the full desktop web player instead of the "open the app" mobile page.

### Data (InnerTube)
- `POST https://music.youtube.com/youtubei/v1/<endpoint>?key=<INNERTUBE_API_KEY>` (`Services/API/YTMusicClient.swift`).
- API key is scraped from the music.youtube.com page HTML (`"INNERTUBE_API_KEY"` regex, line ~2316), not hardcoded.
- Headers (line ~1918–1950):
  - `Cookie`: all youtube.com cookies from the web view store
  - `Authorization: SAPISIDHASH <ts>_<sha1("<ts> <SAPISID> https://music.youtube.com")>`
  - `Origin`/`Referer`/`X-Origin: https://music.youtube.com`, `X-Goog-AuthUser: 0`
- Body always includes `context.client = { clientName: "WEB_REMIX", clientVersion, hl, gl, platform: "DESKTOP", userAgent, ... }`.
- Parsers per surface: `HomeResponseParser`, `SearchResponseParser`, `PlaylistParser`, `ArtistParser`, `LibraryContentParser`, lyrics under `Services/Lyrics`.

### Playback (the important part)
- One long-lived hidden `WKWebView` (`SingletonPlayerWebView`, `Views/MiniPlayerWebView.swift:362`).
- To play a song it navigates to `music.youtube.com/watch?v=<id>` (or uses the site's in-page router for later songs to avoid full reloads).
- Controls are JavaScript run with `evaluateJavaScript` on the page's `<video>` element, falling back to YouTube's `#movie_player` API (`SingletonPlayerWebView+PlaybackControls.swift`: play, pause, next, previous, seek, volume).
- An injected observer script (`SingletonPlayerWebView+ObserverScript.swift`) reports progress, track changes, track end and ads back to Swift through a `WKScriptMessageHandler`.
- The web view must stay **attached to a view hierarchy** to keep playing (`ensureInHierarchy`), so Kaset parks it inside a tiny container view.
- Because the real web player plays the audio, Premium (no ads, quality) and YouTube's anti-bot protections are handled by Google's own code.

## What we take for iOS

| Piece | Plan |
|---|---|
| SAPISIDHASH auth + request headers | Port almost as-is (small, self-contained) |
| API key scraping, `WEB_REMIX` context | Port as-is |
| Response parsers | Port the ones we need (home, search, library, playlist, album, artist, lyrics), adapt models |
| Player JS (controls + observer) | Port the scripts; they are plain JS strings and not Mac-specific |
| `SingletonPlayerWebView` | Rewrite for UIKit: `UIView` container instead of `NSView`, hidden but in the window |
| Now Playing / media keys | Rewrite with `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` + `AVAudioSession(.playback)` |
| AppKit-only features (46 of 382 files: windows, menus, Dock, equalizer, scripting, AI) | Skip |

Kaset is much bigger than we need (about 53k lines of services). We copy small, understood pieces, not the whole app, and keep its MIT notice in copied files.

## iOS risks to test in Stage 2
1. **Background audio**: will the hidden `WKWebView` keep playing when the screen locks? macOS never suspends it; iOS might.
2. **Lock Screen controls**: WebKit may publish its own Now Playing info from the `<video>` element and fight with ours.
3. **Desktop user agent on iPhone**: confirm music.youtube.com serves the desktop player and plays (iOS WebKit has Managed Media Source since 17.1, so it should).

## Fallback: SwiftyTube
If risk 1 fails: SwiftyTube resolves direct stream URLs for the `.music` client, mints PoTokens via a bundled web page, imports our cookie session (`SessionImporter`), and we play with `AVPlayer` (native background audio and Lock Screen support). It is small (~8k lines) and active, but GPL-3.0 (fine for a personal, never-distributed app).
