# Sleek Music App — iOS Port Design

**Date:** 2026-04-24
**Project:** `/Users/sanikakapoor/Emulator/spotify-free/ios/`
**Reference:** `/Users/sanikakapoor/Downloads/Sleek Music App/` (React/Vite/Tailwind)

## Context

The previous design ("Cozy Remote" — cream/sage with serif headers) is being replaced entirely.
The new target is a dark Spotify-style mobile UI modeled on the React/Tailwind reference in
`~/Downloads/Sleek Music App/`. All existing iOS functionality (iTunes search, backend stream
resolve, CoreData/CloudKit playlists + liked tracks, AVPlayer playback + lock-screen controls,
queue management) is preserved — only the visual + UX layer changes.

## Decisions (locked via Q&A)

1. **Theme:** Dark-only. Ignore system Light/Dark. Drop cream palette entirely.
2. **Library tiles:** Only show tiles backed by real data → 2 tiles (Liked Songs, My Playlists).
3. **Artist/Album detail:** Kept and restyled dark. No layout restructure.
4. **Tab bar:** Custom HStack tab bar (not SwiftUI `TabView`) for pixel-perfect reference match.
5. **Typography:** Pure SF Pro (system). No serif anywhere.
6. **Queue reorder:** Always-visible drag handles (not iOS Edit mode).
7. **FullPlayer album art:** Edge-to-edge (`width - 32pt`).
8. **Search:** Live results restyled dark when typing; recents list when empty.
9. **Home:** Data-driven — time-based greeting, real recent plays, real user playlists.
10. **Accent:** Pure white (no Spotify green, no custom accent).
11. **MiniPlayer:** Floating rounded card with side margins, above the tab bar.
12. **Queue entry:** Opens as `fullScreenCover` modal from a tab-bar button (not a 4th tab).

## Design Tokens

```swift
// Colors (new AppTheme)
bg               = #000000            // root
card             = #18181B            // zinc-900 (tab bar, deep surfaces)
surface          = #27272A            // zinc-800 (mini player, queue rows)
surfaceElevated  = #3F3F46 @ 0.6      // zinc-700/60 (hover/active)
ink              = #FFFFFF            // primary text, active icons
ink2             = #9CA3AF            // gray-400 (secondary, inactive)
ink3             = #6B7280            // gray-500 (placeholder, muted)
border           = #27272A            // zinc-800 hairlines

// Gradients
likedGradient     = purple-700 (#7E22CE) → purple-900 (#581C87)
playlistGradient  = blue-600  (#2563EB) → blue-800  (#1E40AF)
fullPlayerBg      = zinc-800 → black (vertical)

// Typography — SF Pro only
h1     = 30pt bold
h2     = 20pt bold
h3     = 16pt semibold
body   = 16pt regular
small  = 14pt regular
caption = 12pt regular

// Radii
sm  = 4pt
md  = 8pt
lg  = 10pt
xl  = 16pt   // album art in FullPlayer

// Spacing
4 / 8 / 12 / 16 / 24 / 32
```

## Architecture

### Root shell
Replace `TabView` with a custom `ZStack`-based shell:
```
ZStack(alignment: .bottom) {
  AppTheme.bg.ignoresSafeArea()
  // Selected-tab content
  Group {
    switch selection {
    case .home:    HomeView()
    case .search:  SearchView()
    case .library: LibraryView()
    }
  }
  .safeAreaInset(.bottom) { Color.clear.frame(height: 128) } // mini + tab clearance

  VStack(spacing: 0) {
    if queue.hasCurrent { MiniPlayerCard() }
    CustomTabBar(selection: $selection, onQueue: { showQueue = true })
  }
}
.fullScreenCover(isPresented: $showFullPlayer) { FullPlayerView() }
.fullScreenCover(isPresented: $showQueue)      { QueueView() }
```

### CustomTabBar
- HStack of 4 tappable items with 12pt padding
- Items: Home (`house.fill`), Search (`magnifyingglass`), Library (`books.vertical.fill`), Queue (`list.bullet`)
- Active: `ink`. Inactive: `ink2`. Queue button always `ink2` (it's modal, not a tab).
- Background: `.ultraThinMaterial` + `card.opacity(0.95)`
- 1pt top border in `border`
- Height: 54pt + safe-area bottom

### Screens

#### Home
- `ScrollView` with `.padding(.top, 48).padding(.horizontal, 16)`
- `greetingText` (30pt bold) — time-based
- "Recently Played" H2 + horizontal `ScrollView(.horizontal)` of 144×144 tile cards
- "Your Playlists" H2 + same shape, real `PlaylistStore` data
- Empty-state handling: hide sections with no data

#### Search
- H1 "Search"
- White pill input (`#FFFFFF` bg, black text, 44pt tall, fully rounded) with leading `magnifyingglass` and trailing `xmark.circle.fill` (clears when tapped)
- When `searchText` empty: "Recent Searches" vertical list (clock-icon tile + query + type + X)
- When non-empty: existing backend search results grouped by Tracks / Albums / Artists, dark-themed rows

#### Library
- H1 "Your Library"
- 1-row, 2-col grid of 96pt-tall gradient tiles:
  - **Liked Songs** — purple gradient, `heart.fill` icon top-left, count bottom-left
  - **My Playlists** — blue gradient, `music.note.list` icon, count
- Tapping Liked → `LikedSongsView` (restyled dark)
- Tapping My Playlists → existing playlists list view
- Below: "Playlists" section header + vertical list (64pt art + name + song count)

#### MiniPlayerCard
- 16pt horizontal margins, 8pt gap above tab bar
- `surface` bg, 10pt radius, subtle shadow
- Row: 48pt rounded art + (title 14 semibold, artist 12 muted) + play/pause button
- 2pt white progress line along the bottom edge
- Tap anywhere (except play button) → opens FullPlayerView

#### FullPlayerView (fullScreenCover)
- Background: linear gradient `zinc-800 → black` (vertical)
- Top row (16pt padding): `chevron.down` (dismiss) / "Now Playing" label / `ellipsis`
- Album art: `(width - 32pt) × (width - 32pt)`, 16pt radius, large shadow
- Title (24 bold) + artist (16 muted) on left, heart toggle on right
- Slider: 2pt track, 14pt thumb; time labels below (left start, right total)
- Transport row (around `Spacer`-separated): shuffle (muted when off, white when on) · `backward.fill` 28pt · **64pt white circle with black `play.fill`/`pause.fill`** · `forward.fill` 28pt · repeat (muted/white/white-with-1)

#### QueueView (fullScreenCover)
- Same gradient bg
- Header row: `chevron.down` + "Queue"
- "NOW PLAYING" muted small-caps label + single card row
- "NEXT UP" label + draggable rows with leading `line.3.horizontal` grip handle (always visible)
- Implementation: SwiftUI `List` with `.environment(\.editMode, .constant(.active))` so reorder handles show without an Edit toggle; `.onMove` → `QueueManager.move`
- Swipe-to-delete on each row → `QueueManager.remove`

#### Artist/Album/Playlist Detail
- Restyle only. No layout changes.
- Background → `bg`; cards → `surface`; text → `ink`/`ink2`
- 240pt hero art, 16pt radius
- Section headers → 20pt bold white
- Track rows use restyled `TrackRow`

### Primitives

**TrackRow (rewrite):**
- 44pt art, 12pt gap
- Title 14 semibold `ink`, artist 12 `ink2`, both lineLimit 1
- Trailing: `ellipsis` button opening an "Add to Queue" action sheet (preserves prior polish-pass behavior)
- Tap row → play track

**ArtworkView (adjust):**
- Placeholder bg → `surface` with `music.note` icon in `ink2`

**Delete:** `CozyTopBar.swift`, `CozySurface.swift`, `CozyPrimaryButton.swift`, and any other `Cozy*` primitive files.

### New service: RecentPlaysStore

Small persisted FIFO of recent Track play-starts.
- Location: `Services/RecentPlaysStore.swift`
- API:
  ```swift
  @MainActor final class RecentPlaysStore: ObservableObject {
    static let shared = RecentPlaysStore()
    @Published private(set) var items: [Track]
    func recordPlay(_ track: Track)  // capacity 20, dedupe by track id, push-to-front
  }
  ```
- Persistence: UserDefaults JSON encode/decode
- Called from `AudioPlayer.play(_:)` — exactly one new line at top of the method.

## File change inventory

| File | Scope |
|---|---|
| `Views/Theme.swift` | Rewrite `AppTheme` with dark tokens; remove serif helpers; remove cream colors |
| `App/SpotifyFreeApp.swift` | Replace `TabView` with custom ZStack shell; add `showQueue`/`showFullPlayer` state |
| `Views/TabRouter.swift` | Simplify enum to 3 tabs (Home/Search/Library); remove Queue case |
| `Views/HomeView.swift` | Rewrite: time-based greeting + 2 data-driven carousels |
| `Views/SearchView.swift` | Rewrite: white pill + recents/results with dark restyle |
| `Views/LibraryView.swift` | Rewrite: 2-tile gradient grid + playlists list |
| `Views/NowPlayingView.swift` | Split into `MiniPlayerCard` + `FullPlayerView`; match reference geometry |
| `Views/QueueView.swift` | Rewrite as fullScreenCover with always-visible drag handles |
| `Views/ArtistDetailView.swift` | Restyle dark (tokens only) |
| `Views/AlbumDetailView.swift` | Restyle dark |
| `Views/PlaylistDetailView.swift` | Restyle dark |
| `Views/LikedSongsView.swift` | Restyle dark |
| `Views/Design/TrackRow.swift` | Rewrite dark |
| `Views/Design/ArtworkView.swift` | Placeholder bg tweak |
| `Views/Design/Cozy*.swift` | **Delete** |
| `Services/RecentPlaysStore.swift` | **New** |
| `Services/AudioPlayer.swift` | 1-line addition: `RecentPlaysStore.shared.recordPlay(track)` in `play(_:)` |

**Untouched:** `project.yml`, `Info.plist`, `Models/*`, `Persistence/*`, `Services/BackendClient.swift`, `Services/iTunesClient.swift`, `Services/StreamResolver.swift`, `Services/QueueManager.swift`, backend.

## Constraints (from project memory)

- `project.yml` `info.properties.SPOTIFY_FREE_BACKEND_URL=$(SPOTIFY_FREE_BACKEND_URL)` and
  `settings.base.SPOTIFY_FREE_BACKEND_URL=https://free-spotify.duckdns.org` must not change —
  any loss triggers the localhost regression.
- Verify `Info.plist` still contains `SPOTIFY_FREE_BACKEND_URL` after any `xcodegen generate`.
- `xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree -destination 'generic/platform=iOS Simulator' -configuration Debug build` must pass with 0 errors before ship.

## Verification

1. **Build:** `xcodegen generate && xcodebuild … build` → BUILD SUCCEEDED, 0 warnings, backend URL preserved.
2. **Visual:** dark palette everywhere; no cream remnants; no serif.
3. **Tab bar:** flush at bottom, zinc-900 blur, 4 items (Home/Search/Library/Queue); Queue button opens modal (doesn't swap tab content).
4. **Home:** time-based greeting + real recent plays + real user playlists; empty-state hides sections.
5. **Search:** empty → recents list; typing → dark grouped live results; clear-X works.
6. **Library:** 2 gradient tiles with live counts; tapping each opens the corresponding list.
7. **MiniPlayer:** floating card with side margins, 2pt white progress line at bottom; tap opens FullPlayer; does not track the keyboard.
8. **FullPlayer:** edge-to-edge album art, gradient bg, big white circular play button.
9. **Queue:** modal with always-visible grip handles; drag reorders; swipe-delete works.
10. **Artist/Album/Playlist detail:** dark palette, 240pt hero, track list functional.
11. **RecentPlaysStore:** playing a track updates Home's "Recently Played" on next view.
12. **Playback regressions from polish pass:** repeat-one still restarts same track; next track auto-starts; duration correct; scrub-then-play keeps timer running.

## Out of scope

- Light mode (explicitly cut)
- "Following artists" and "Saved Albums" concepts (not backed by data model; cut)
- Playlist creation UI redesign (existing flow preserved, just restyled)
- Onboarding / auth (app has none)
- Accent color / theming customization

## Open points (to resolve at implementation time)

- Exact SF Symbol choices for Queue tab icon (`list.bullet` vs `text.append` vs `music.note.list`) — pick whichever reads best at 24pt
- FullPlayer `ellipsis` menu contents (likely: Add to Playlist, Go to Artist, Go to Album, Share). Non-blocking; falls back to existing NowPlayingView menu items.
