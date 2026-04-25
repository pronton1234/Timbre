# Sleek Music App — iOS Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Cozy Remote cream-and-serif visual layer in the spotify-free iOS app with a dark Spotify-style UI modeled on `~/Downloads/Sleek Music App/`, preserving all existing playback/search/library functionality.

**Architecture:** Rewrite the `AppTheme` tokens to a dark palette, delete the `Cozy*` primitives, replace `TabView` with a custom HStack tab bar inside a `ZStack` shell, and rewrite each screen top-down against the new tokens. Services/models/persistence untouched except adding `RecentPlaysStore` and a 1-line hook in `AudioPlayer.play()`.

**Tech Stack:** Swift 5.9, SwiftUI (iOS 16+), AVFoundation, MediaPlayer, CoreData, xcodegen, xcodebuild.

**Not a git repo** — skip all `git` commit steps. Instead, each task ends with a compile check.

**Spec:** `docs/superpowers/specs/2026-04-24-sleek-music-app-ios-port-design.md`

---

## Phase 1 — Foundation: Tokens + Shell

### Task 1: Rewrite `AppTheme` with dark tokens

**Files:**
- Modify: `ios/SpotifyFree/Views/Theme.swift` (full rewrite, 142 → ~110 lines)

- [ ] **Step 1.1: Replace the entire contents of `Theme.swift` with:**

```swift
import SwiftUI
import UIKit

/// Design tokens for the "Sleek Music App" look — dark Spotify-style palette,
/// pure SF Pro (system) typography. Keep this file presentational only.
enum AppTheme {
    // MARK: Colors

    /// Root background — pure black.
    static let bg               = Color.black
    /// Legacy alias used by older call-sites still being rewritten.
    static let background       = Color.black
    /// Deep card (tab bar, nav chrome) — zinc-900.
    static let card             = Color(red: 0.094, green: 0.094, blue: 0.106) // #18181B
    /// Surface (mini player, queue rows) — zinc-800.
    static let surface          = Color(red: 0.153, green: 0.153, blue: 0.165) // #27272A
    /// Elevated/hover — zinc-700 @ 60%.
    static let surfaceElevated  = Color(red: 0.247, green: 0.247, blue: 0.275).opacity(0.6) // #3F3F46 @ 0.6

    /// Primary text, active icons.
    static let ink              = Color.white
    /// Legacy alias kept so older call-sites compile.
    static let text             = Color.white
    /// Secondary text, inactive icons — gray-400.
    static let ink2             = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF
    static let textSecondary    = Color(red: 0.612, green: 0.639, blue: 0.686)
    /// Tertiary text, placeholder — gray-500.
    static let ink3             = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    /// Hairline — zinc-800 (same as surface).
    static let hair             = Color(red: 0.153, green: 0.153, blue: 0.165)
    static let divider          = Color(red: 0.153, green: 0.153, blue: 0.165)
    /// Accent (pure white — no Spotify green).
    static let accent           = Color.white
    static let accentTint       = Color(red: 0.247, green: 0.247, blue: 0.275).opacity(0.6)

    // MARK: Gradients (Library category tiles)

    static let likedGradient = LinearGradient(
        colors: [Color(red: 0.494, green: 0.133, blue: 0.808),   // purple-700 #7E22CE
                 Color(red: 0.345, green: 0.109, blue: 0.529)],  // purple-900 #581C87
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let playlistGradient = LinearGradient(
        colors: [Color(red: 0.145, green: 0.388, blue: 0.921),   // blue-600 #2563EB
                 Color(red: 0.118, green: 0.251, blue: 0.686)],  // blue-800 #1E40AF
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let fullPlayerBg = LinearGradient(
        colors: [Color(red: 0.153, green: 0.153, blue: 0.165),   // zinc-800
                 Color.black],
        startPoint: .top, endPoint: .bottom)

    // MARK: Shadows

    static let shadowSoft   = Color.black.opacity(0.30)
    static let shadowStrong = Color.black.opacity(0.60)

    // MARK: Fonts — SF Pro (system). No serif, no custom font.

    /// Primary text helper. `weight` maps directly to SwiftUI's Font.Weight.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    /// Back-compat aliases used by old call-sites. All resolve to system sans.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    /// Pre-baked styles.
    static let display1 = Font.system(size: 30, weight: .bold)
    static let display2 = Font.system(size: 20, weight: .bold)
    static let display3 = Font.system(size: 24, weight: .bold)
    static let display  = Font.system(size: 30, weight: .bold)
    static let section  = Font.system(size: 20, weight: .bold)
}

// MARK: - UIKit appearance

/// Dark UIKit appearance so NavigationStack chrome + any residual UITabBar
/// inherits the sleek palette. The custom HStack tab bar handles the real
/// bottom nav; this is only a safety net.
enum AppAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor.black
        nav.shadowColor = .clear

        let largeFont  = UIFont.systemFont(ofSize: 30, weight: .bold)
        let inlineFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let textColor  = UIColor.white

        nav.largeTitleTextAttributes = [.font: largeFont,  .foregroundColor: textColor]
        nav.titleTextAttributes      = [.font: inlineFont, .foregroundColor: textColor]

        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance    = nav
        UINavigationBar.appearance().tintColor            = .white

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(AppTheme.card)
        tab.shadowColor = UIColor(AppTheme.hair)

        let item = tab.stackedLayoutAppearance
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        item.normal.iconColor = UIColor(AppTheme.ink2)
        item.normal.titleTextAttributes   = [.foregroundColor: UIColor(AppTheme.ink2)]

        UITabBar.appearance().standardAppearance    = tab
        UITabBar.appearance().scrollEdgeAppearance  = tab
        UITabBar.appearance().isTranslucent         = false

        let seg = UISegmentedControl.appearance()
        seg.backgroundColor          = UIColor(AppTheme.surface)
        seg.selectedSegmentTintColor = .white
        seg.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)

        UITableView.appearance().backgroundColor     = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }
}

// MARK: - Helpers

extension View {
    /// Paints the black app background behind a scrolling view (List/ScrollView).
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg.ignoresSafeArea())
    }
}
```

- [ ] **Step 1.2: Compile check**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  xcodegen generate && \
  xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree \
    -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -20
```

Expected: It's fine if the rest of the app fails to compile right now — we're going to rewrite callers in later tasks. **Only confirm that `Theme.swift` itself has no syntax errors** by checking the output contains `Theme.swift` errors *only* if the Theme file itself is broken. If errors are only from other files using removed symbols (e.g. `AppTheme.display(` with no arg, `Manrope-Bold` references gone), that's expected.

### Task 2: Delete cozy primitives

**Files:**
- Delete: `ios/SpotifyFree/Views/Design/CozyTopBar.swift`
- Delete: `ios/SpotifyFree/Views/Design/CozyButtons.swift`
- Delete: `ios/SpotifyFree/Views/Design/PillTabBar.swift`
- Delete: `ios/SpotifyFree/Views/Design/TintBackground.swift`

- [ ] **Step 2.1: Delete the files**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios/SpotifyFree/Views/Design && \
  rm CozyTopBar.swift CozyButtons.swift PillTabBar.swift TintBackground.swift
```

- [ ] **Step 2.2: Regenerate xcodeproj so file list is clean**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodegen generate
```
Expected: `Generated project successfully`.

### Task 3: Rewrite `TabRouter.swift` — 3 tabs only

**Files:**
- Modify: `ios/SpotifyFree/Views/Design/TabRouter.swift` (full rewrite, 15 lines)

- [ ] **Step 3.1: Replace contents with:**

```swift
import SwiftUI

/// Root-level tabs. Queue is NOT a tab in the sleek design — it opens as a
/// fullScreenCover modal from the tab bar. Shared across the app via
/// `@EnvironmentObject` so any screen can programmatically switch tabs.
enum RootTab: Hashable {
    case home
    case search
    case library
}

final class TabRouter: ObservableObject {
    @Published var selected: RootTab = .home
}
```

- [ ] **Step 3.2: Regenerate + compile check**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  xcodegen generate && \
  xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree \
    -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | \
    grep -E '(error:|Build succeeded)' | head -10
```

Expected: Build will still fail because `SpotifyFreeApp.swift` and some views reference `RootTab.queue`. Next task fixes those.

### Task 4: Create custom `SleekTabBar` component

**Files:**
- Create: `ios/SpotifyFree/Views/Design/SleekTabBar.swift`

- [ ] **Step 4.1: Write the file:**

```swift
import SwiftUI

/// Bottom tab bar matching the Sleek Music App reference:
/// 4 tappable items (Home, Search, Library, Queue). The first 3 switch the
/// selected `RootTab`; the 4th (Queue) triggers a modal via `onQueueTap`
/// and does NOT select a tab.
struct SleekTabBar: View {
    @Binding var selected: RootTab
    var onQueueTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .home,    icon: "house.fill",             label: "Home")
            tabButton(tab: .search,  icon: "magnifyingglass",        label: "Search")
            tabButton(tab: .library, icon: "books.vertical.fill",    label: "Library")
            queueButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            ZStack {
                AppTheme.card.opacity(0.95)
                Rectangle().fill(.ultraThinMaterial).opacity(0.6)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.hair)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tabButton(tab: RootTab, icon: String, label: String) -> some View {
        let isActive = (selected == tab)
        Button {
            selected = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(label)
                    .font(AppTheme.text(11, weight: .medium))
            }
            .foregroundStyle(isActive ? AppTheme.ink : AppTheme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var queueButton: some View {
        Button(action: onQueueTap) {
            VStack(spacing: 2) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 22, weight: .regular))
                Text("Queue")
                    .font(AppTheme.text(11, weight: .medium))
            }
            .foregroundStyle(AppTheme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4.2: Regenerate**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodegen generate`
Expected: `Generated project successfully`.

### Task 5: Restructure `SpotifyFreeApp.swift` to use ZStack shell

**Files:**
- Modify: `ios/SpotifyFree/App/SpotifyFreeApp.swift` (lines 44-64 `RootTabView` rewrite; lines 19-31 scene body unchanged except remove `.tint`)

- [ ] **Step 5.1: Replace the entire contents with:**

```swift
import SwiftUI
import AVFoundation
import UIKit

@main
struct SpotifyFreeApp: App {
    @StateObject private var player = AudioPlayer.shared
    @StateObject private var queue = QueueManager.shared
    @StateObject private var router = TabRouter()
    let persistence = PersistenceController.shared

    init() {
        FontLoader.registerBundledFonts()
        configureAudioSession()
        AppAppearance.configure()
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppTheme.bg.ignoresSafeArea()
                RootShell()
            }
            .environmentObject(player)
            .environmentObject(queue)
            .environmentObject(router)
            .environment(\.managedObjectContext, persistence.container.viewContext)
            .preferredColorScheme(.dark)
            .tint(.white)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("AudioSession configure failed: \(error)")
        }
    }
}

/// ZStack shell: selected-tab content at the bottom of the stack, with the
/// MiniPlayer + custom tab bar overlaid. FullPlayer and Queue come up as
/// fullScreenCover modals.
struct RootShell: View {
    @EnvironmentObject var router: TabRouter
    @EnvironmentObject var queue: QueueManager
    @State private var showQueue = false
    @State private var showFullPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Selected tab content
            Group {
                switch router.selected {
                case .home:    HomeView()
                case .search:  SearchView()
                case .library: LibraryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MiniPlayer + tab bar stack
            VStack(spacing: 0) {
                if queue.currentIndex >= 0, queue.queue.indices.contains(queue.currentIndex) {
                    MiniPlayerCard(onTap: { showFullPlayer = true })
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
                SleekTabBar(selected: $router.selected, onQueueTap: { showQueue = true })
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(onDismiss: { showFullPlayer = false })
        }
        .fullScreenCover(isPresented: $showQueue) {
            QueueView(onDismiss: { showQueue = false })
        }
    }
}
```

- [ ] **Step 5.2: Compile check**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree \
    -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | \
    grep -E '(error:|BUILD)' | head -20
```

Expected: Errors from `MiniPlayerCard`, `FullPlayerView`, `QueueView` not defined (we'll define them in Phase 5) — OK. No errors from `SpotifyFreeApp.swift` itself.

---

## Phase 2 — Primitives

### Task 6: Rewrite `TrackRow.swift` for dark palette

**Files:**
- Modify: `ios/SpotifyFree/Views/Design/TrackRow.swift` (full rewrite, ~56 lines)

- [ ] **Step 6.1: Replace contents with:**

```swift
import SwiftUI

/// A single track row in the Sleek dark palette:
/// 44×44 art tile, title (semibold 14 white), artist (12 gray), optional
/// leading index, trailing ellipsis (opens "Add to Queue" action) or a
/// custom accessory.
struct TrackRow: View {
    let track: Track
    var index: Int? = nil
    var showArtwork: Bool = true
    var onTap: () -> Void = {}
    var onAddToQueue: (() -> Void)? = nil
    var accessory: AnyView? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let index {
                    Text("\(index)")
                        .font(AppTheme.text(14, weight: .medium))
                        .foregroundStyle(AppTheme.ink2)
                        .frame(width: 22, alignment: .trailing)
                        .monospacedDigit()
                }
                if showArtwork {
                    ArtworkView(url: track.artworkUrl, size: 44)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(AppTheme.text(14, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(track.artistName)
                        .font(AppTheme.text(12))
                        .foregroundStyle(AppTheme.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let accessory {
                    accessory
                } else if let onAddToQueue {
                    Button(action: onAddToQueue) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.ink2)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 6.2: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree -destination 'generic/platform=iOS Simulator' build 2>&1 | grep 'TrackRow.swift.*error' | head -5`

Expected: no lines output (TrackRow compiles). Other errors from unwritten MiniPlayer/FullPlayer/etc still OK.

### Task 7: Adjust `ArtworkView.swift` placeholder for dark

**Files:**
- Read first: `ios/SpotifyFree/Views/ArtworkView.swift`
- Modify: same file, ensure placeholder uses `AppTheme.surface` bg + `AppTheme.ink2` icon

- [ ] **Step 7.1: Read current implementation**

Run: `Read` on `ios/SpotifyFree/Views/ArtworkView.swift`

- [ ] **Step 7.2: Edit placeholder colors**

If the placeholder `Rectangle`/`RoundedRectangle` uses `AppTheme.accentTint` or similar cream tones, change the fill to `AppTheme.surface`. If there's an SF Symbol overlay (e.g. `music.note`), change its `.foregroundStyle` to `AppTheme.ink2`.

Example Edit (adapt to actual source):
```swift
// Old:  .fill(AppTheme.accentTint)
// New:  .fill(AppTheme.surface)
```
and
```swift
// Old:  .foregroundStyle(AppTheme.ink3)
// New:  .foregroundStyle(AppTheme.ink2)
```

- [ ] **Step 7.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree -destination 'generic/platform=iOS Simulator' build 2>&1 | grep 'ArtworkView.swift.*error' | head -5`

Expected: no lines output.

---

## Phase 3 — New service: RecentPlaysStore

### Task 8: Create `RecentPlaysStore.swift`

**Files:**
- Create: `ios/SpotifyFree/Services/RecentPlaysStore.swift`

- [ ] **Step 8.1: Write the file:**

```swift
import Foundation
import Combine

/// Tracks the last N played tracks (push-to-front, dedupe by id, cap 20).
/// Persisted to UserDefaults as JSON. Home view reads `items` to populate
/// its "Recently Played" carousel.
@MainActor
final class RecentPlaysStore: ObservableObject {
    static let shared = RecentPlaysStore()

    @Published private(set) var items: [Track] = []

    private let key = "recentPlaysStore.v1"
    private let capacity = 20

    private init() {
        restore()
    }

    func recordPlay(_ track: Track) {
        items.removeAll { $0.id == track.id }
        items.insert(track, at: 0)
        if items.count > capacity { items = Array(items.prefix(capacity)) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Track].self, from: data)
        else { return }
        items = decoded
    }
}
```

- [ ] **Step 8.2: Regenerate + compile check**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  xcodegen generate && \
  xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree \
    -destination 'generic/platform=iOS Simulator' build 2>&1 | \
    grep 'RecentPlaysStore.swift.*error' | head -5
```

Expected: no lines output.

### Task 9: Wire `RecentPlaysStore` into `AudioPlayer.play()`

**Files:**
- Modify: `ios/SpotifyFree/Services/AudioPlayer.swift` (1 line added at top of `play(_:)`)

- [ ] **Step 9.1: Read the current `play(_:)` method**

Run: `Grep` for `func play` in `Services/AudioPlayer.swift` with `-n` and `-C 3`.

- [ ] **Step 9.2: Add one line at the top of `play(_ track: Track)`**

Use `Edit` to insert right after the opening `{` of the method:
```swift
        RecentPlaysStore.shared.recordPlay(track)
```

Example edit target (adapt to actual indentation):
```swift
// Old:
    func play(_ track: Track) async {
        // existing body...

// New:
    func play(_ track: Track) async {
        RecentPlaysStore.shared.recordPlay(track)
        // existing body...
```

- [ ] **Step 9.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree -destination 'generic/platform=iOS Simulator' build 2>&1 | grep 'AudioPlayer.swift.*error' | head -5`

Expected: no lines output.

---

## Phase 4 — Screens

### Task 10: Rewrite `HomeView.swift`

**Files:**
- Modify: `ios/SpotifyFree/Views/HomeView.swift` (full rewrite, ~219 → ~140 lines)

- [ ] **Step 10.1: Replace the entire contents with:**

```swift
import SwiftUI

/// Sleek dark Home screen:
///   • Time-based greeting H1 (30pt bold white)
///   • "Recently Played" — horizontal scroll of 144pt art tiles, from RecentPlaysStore
///   • "Your Playlists" — horizontal scroll of 144pt tiles, from CoreData Playlists
struct HomeView: View {
    @EnvironmentObject var queue: QueueManager
    @EnvironmentObject var router: TabRouter
    @StateObject private var recents = RecentPlaysStore.shared

    @FetchRequest(
        entity: PlaylistEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaylistEntity.createdAt, ascending: false)]
    ) private var playlists: FetchedResults<PlaylistEntity>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(greeting)
                    .font(AppTheme.text(30, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.top, 48)

                if !recents.items.isEmpty {
                    section(title: "Recently Played") {
                        ForEach(recents.items) { track in
                            carouselTile(
                                artworkUrl: track.artworkUrl,
                                title: track.name,
                                subtitle: track.artistName,
                                onTap: { Task { await queue.playNow([track]) } }
                            )
                        }
                    }
                }

                if !playlists.isEmpty {
                    section(title: "Your Playlists") {
                        ForEach(playlists) { pl in
                            NavigationLink {
                                PlaylistDetailView(playlist: pl)
                            } label: {
                                carouselTile(
                                    artworkUrl: pl.coverURL,
                                    title: pl.name ?? "Untitled",
                                    subtitle: "\(pl.tracks?.count ?? 0) songs",
                                    onTap: {}
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Color.clear.frame(height: 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.bg.ignoresSafeArea())
    }

    // MARK: - Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    // MARK: - Section / Tile helpers

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.text(20, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func carouselTile(
        artworkUrl: URL?,
        title: String,
        subtitle: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: artworkUrl, size: 144)
                    .frame(width: 144, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
            }
            .frame(width: 144, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// Helper extension for PlaylistEntity cover URL. If this property already
// exists on PlaylistEntity, delete this extension.
private extension PlaylistEntity {
    var coverURL: URL? {
        if let s = value(forKey: "coverUrl") as? String { return URL(string: s) }
        return nil
    }
}
```

- [ ] **Step 10.2: Verify `PlaylistEntity.coverURL` is not already defined**

Run: `Grep` pattern `coverURL` in `ios/SpotifyFree/` with `-n`. If it already exists on the entity or another file, delete the `private extension PlaylistEntity` block from `HomeView.swift`.

- [ ] **Step 10.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree -destination 'generic/platform=iOS Simulator' build 2>&1 | grep 'HomeView.swift.*error' | head -10`

Expected: no lines output. If there are errors about `PlaylistEntity` property names (e.g. `createdAt`, `name`, `tracks`), read `Persistence/Playlists.xcdatamodeld` or the `PlaylistEntity` extension to confirm the actual attribute names, then adjust.

### Task 11: Rewrite `SearchView.swift`

**Files:**
- Modify: `ios/SpotifyFree/Views/SearchView.swift` (full rewrite, ~385 → ~260 lines)

- [ ] **Step 11.1: Read the current `SearchView.swift`**

Run: `Read` on `ios/SpotifyFree/Views/SearchView.swift` to understand the existing search data flow (backend call, result types). Keep that flow; only rewrite the view structure.

- [ ] **Step 11.2: Replace contents**

Preserve the existing `@State` vars for `searchText`, `results`, `recentSearches`, `isLoading`, `recents` UserDefaults key, and the backend search function. Replace the entire `body` with the sleek layout:

```swift
// In body:
ZStack {
    AppTheme.bg.ignoresSafeArea()

    VStack(alignment: .leading, spacing: 16) {
        header
        searchBar
        if searchText.isEmpty {
            recentsSection
        } else {
            resultsScroll
        }
        Spacer(minLength: 0)
    }
    .padding(.top, 48)
}
```

Where:

```swift
private var header: some View {
    Text("Search")
        .font(AppTheme.text(30, weight: .bold))
        .foregroundStyle(AppTheme.ink)
        .padding(.horizontal, 16)
}

@FocusState private var fieldFocused: Bool

private var searchBar: some View {
    HStack(spacing: 12) {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink3)
            TextField("What do you want to listen to?", text: $searchText)
                .font(AppTheme.text(15))
                .foregroundStyle(.black)
                .focused($fieldFocused)
                .submitLabel(.search)
                .onSubmit { runSearch() }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.ink3)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.white)
        .clipShape(Capsule())

        if fieldFocused {
            Button("Cancel") {
                searchText = ""; fieldFocused = false
            }
            .font(AppTheme.text(15, weight: .medium))
            .foregroundStyle(AppTheme.ink)
        }
    }
    .padding(.horizontal, 16)
    .animation(.easeInOut(duration: 0.15), value: fieldFocused)
}

private var recentsSection: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Searches")
                .font(AppTheme.text(20, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(recentSearches, id: \.self) { q in
                    recentRow(q)
                }
            }
        }
    }
}

private func recentRow(_ query: String) -> some View {
    HStack(spacing: 12) {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(AppTheme.surface)
            Image(systemName: "clock")
                .foregroundStyle(AppTheme.ink2)
        }
        .frame(width: 48, height: 48)

        VStack(alignment: .leading, spacing: 2) {
            Text(query)
                .font(AppTheme.text(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Text("Recent")
                .font(AppTheme.text(12))
                .foregroundStyle(AppTheme.ink2)
        }
        Spacer()
        Button { removeRecent(query) } label: {
            Image(systemName: "xmark")
                .foregroundStyle(AppTheme.ink2)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .contentShape(Rectangle())
    .onTapGesture {
        searchText = query
        runSearch()
    }
}

private var resultsScroll: some View {
    // Reuse existing grouped-results rendering here, restyled:
    // Sections: Tracks, Albums, Artists. Each row: ArtworkView(44pt) + title/subtitle,
    // backgrounds transparent, text ink/ink2.
    // If the current SearchView already has section builders, retain them but swap
    // any Cozy surface backgrounds for `.background(Color.clear)` and text colors
    // to AppTheme.ink / .ink2.
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            if !tracks.isEmpty {
                resultsGroup(title: "Songs") {
                    ForEach(tracks) { t in
                        TrackRow(track: t, onTap: { Task { await queue.playNow([t]) } })
                            .padding(.horizontal, 16)
                    }
                }
            }
            if !albums.isEmpty {
                resultsGroup(title: "Albums") {
                    ForEach(albums) { a in
                        NavigationLink { AlbumDetailView(album: a) } label: {
                            albumRow(a)
                        }.buttonStyle(.plain)
                    }
                }
            }
            if !artists.isEmpty {
                resultsGroup(title: "Artists") {
                    ForEach(artists) { ar in
                        NavigationLink { ArtistDetailView(artist: ar) } label: {
                            artistRow(ar)
                        }.buttonStyle(.plain)
                    }
                }
            }
            Color.clear.frame(height: 160)
        }
    }
}

@ViewBuilder
private func resultsGroup<Content: View>(title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(AppTheme.text(20, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 16)
        content()
    }
}

private func albumRow(_ a: Album) -> some View {
    HStack(spacing: 12) {
        ArtworkView(url: a.artworkUrl, size: 44)
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        VStack(alignment: .leading, spacing: 2) {
            Text(a.name)
                .font(AppTheme.text(14, weight: .semibold))
                .foregroundStyle(AppTheme.ink).lineLimit(1)
            Text(a.artistName)
                .font(AppTheme.text(12))
                .foregroundStyle(AppTheme.ink2).lineLimit(1)
        }
        Spacer()
    }.padding(.horizontal, 16)
}

private func artistRow(_ ar: Artist) -> some View {
    HStack(spacing: 12) {
        ArtworkView(url: ar.artworkUrl, size: 44)
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        Text(ar.name)
            .font(AppTheme.text(14, weight: .semibold))
            .foregroundStyle(AppTheme.ink).lineLimit(1)
        Spacer()
    }.padding(.horizontal, 16)
}
```

Preserve the existing data-loading functions (`runSearch`, `addRecent`, `removeRecent`, backend-search wiring). If the existing file doesn't split results into `tracks`/`albums`/`artists` state properties, add them and update `runSearch` to populate all three.

- [ ] **Step 11.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'SearchView.swift.*error' | head -20`

Expected: no lines output. If errors appear about `Album` / `Artist` model properties, read `Models/Album.swift` and `Models/Artist.swift` and adjust property names.

### Task 12: Rewrite `LibraryView.swift`

**Files:**
- Modify: `ios/SpotifyFree/Views/LibraryView.swift` (full rewrite, ~188 → ~150 lines)

- [ ] **Step 12.1: Replace contents with:**

```swift
import SwiftUI

/// Sleek dark Library:
///   • H1 "Your Library"
///   • Row of 2 gradient category tiles (Liked Songs purple, My Playlists blue)
///   • Section "Playlists" — vertical list of real playlists
struct LibraryView: View {
    @EnvironmentObject var queue: QueueManager

    @FetchRequest(
        entity: PlaylistEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaylistEntity.createdAt, ascending: false)]
    ) private var playlists: FetchedResults<PlaylistEntity>

    @FetchRequest(
        entity: LikedTrackEntity.entity(),
        sortDescriptors: []
    ) private var liked: FetchedResults<LikedTrackEntity>

    @State private var showLiked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your Library")
                    .font(AppTheme.text(30, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.top, 48)

                HStack(spacing: 12) {
                    categoryTile(
                        gradient: AppTheme.likedGradient,
                        icon: "heart.fill",
                        title: "Liked Songs",
                        count: "\(liked.count) \(liked.count == 1 ? "song" : "songs")",
                        onTap: { showLiked = true }
                    )
                    NavigationLink {
                        PlaylistsIndexView()
                    } label: {
                        categoryTile(
                            gradient: AppTheme.playlistGradient,
                            icon: "music.note.list",
                            title: "My Playlists",
                            count: "\(playlists.count) \(playlists.count == 1 ? "playlist" : "playlists")",
                            onTap: {}
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                if !playlists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Playlists")
                                .font(AppTheme.text(20, weight: .bold))
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        VStack(spacing: 0) {
                            ForEach(playlists) { pl in
                                NavigationLink { PlaylistDetailView(playlist: pl) } label: {
                                    playlistRow(pl)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }

                Color.clear.frame(height: 160)
            }
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .sheet(isPresented: $showLiked) {
            NavigationStack { LikedTracksView() }
        }
    }

    // MARK: - Tiles

    private func categoryTile(
        gradient: LinearGradient,
        icon: String,
        title: String,
        count: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.text(14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(count)
                        .font(AppTheme.text(11))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 96)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func playlistRow(_ pl: PlaylistEntity) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: pl.coverURL, size: 56)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(pl.name ?? "Untitled")
                    .font(AppTheme.text(15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text("\(pl.tracks?.count ?? 0) songs")
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Full-width list of all user playlists, opened from the "My Playlists"
/// gradient tile. (Extracted from the previous LibraryView so the tile can
/// route to a dedicated screen.)
struct PlaylistsIndexView: View {
    @FetchRequest(
        entity: PlaylistEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaylistEntity.createdAt, ascending: false)]
    ) private var playlists: FetchedResults<PlaylistEntity>

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(playlists) { pl in
                    NavigationLink { PlaylistDetailView(playlist: pl) } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: pl.coverURL, size: 56)
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name ?? "Untitled")
                                    .font(AppTheme.text(15, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("\(pl.tracks?.count ?? 0) songs")
                                    .font(AppTheme.text(12))
                                    .foregroundStyle(AppTheme.ink2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("My Playlists")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Reuse the coverURL helper defined next to HomeView; no redefinition here.
```

- [ ] **Step 12.2: Check `LikedTracksView` exists**

Run: `Grep` pattern `struct LikedTracksView` in `ios/SpotifyFree/Views/`. If it doesn't exist, either:
(a) reuse the existing liked-songs UI from the old LibraryView by extracting it into a `LikedTracksView.swift`, or
(b) replace the sheet body with the appropriate existing view name.

- [ ] **Step 12.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'LibraryView.swift.*error' | head -10`

Expected: no lines output. Adjust CoreData property names if needed.

---

## Phase 5 — Playback UI

### Task 13: Rewrite `NowPlayingView.swift` → split into `MiniPlayerCard` + `FullPlayerView`

**Files:**
- Modify: `ios/SpotifyFree/Views/NowPlayingView.swift` (full rewrite, ~408 lines)

- [ ] **Step 13.1: Read the current file to note preserved helpers**

Run: `Read` on `ios/SpotifyFree/Views/NowPlayingView.swift`. Identify: the "more" menu items (Add to Playlist, Go to Artist, Share), the like-heart wiring, and the slider drag handling (`scrubTarget` / `onEditingChanged`). These must be preserved in FullPlayerView.

- [ ] **Step 13.2: Replace the file contents with the split implementation**

```swift
import SwiftUI
import MediaPlayer

// MARK: - MiniPlayerCard

/// Floating rounded mini-player that sits above the tab bar.
struct MiniPlayerCard: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var queue: QueueManager
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ArtworkView(url: player.currentTrack?.artworkUrl, size: 40)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.name ?? "—")
                        .font(AppTheme.text(13, weight: .semibold))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(1)
                    Text(player.currentTrack?.artistName ?? "")
                        .font(AppTheme.text(11))
                        .foregroundStyle(AppTheme.ink2)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            // thin white progress line
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(AppTheme.hair)
                    Rectangle()
                        .fill(AppTheme.ink)
                        .frame(width: geo.size.width * CGFloat(progressFraction))
                }
            }
            .frame(height: 2)
        }
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: AppTheme.shadowSoft, radius: 8, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private var progressFraction: Double {
        let d = player.duration
        guard d > 0 else { return 0 }
        return min(max(player.position / d, 0), 1)
    }
}

// MARK: - FullPlayerView

/// Full-screen player: gradient bg, edge-to-edge album art, big white circle
/// play button. Presented as fullScreenCover from RootShell.
struct FullPlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var queue: QueueManager
    var onDismiss: () -> Void

    @State private var scrubTarget: Double? = nil
    @State private var isLiked = false

    var body: some View {
        ZStack {
            AppTheme.fullPlayerBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                artwork
                Spacer(minLength: 16)
                titleBlock
                slider
                transport
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
        }
        .onAppear { isLiked = LikesStore.shared.isLiked(player.currentTrack?.id ?? 0) }
    }

    // MARK: Subviews

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text("Now Playing")
                .font(AppTheme.text(13, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Menu {
                if let t = player.currentTrack {
                    Button { LikesStore.shared.toggle(trackId: t.id); isLiked.toggle() } label: {
                        Label(isLiked ? "Unlike" : "Like", systemImage: "heart")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.top, 8)
    }

    private var artwork: some View {
        GeometryReader { geo in
            let size = geo.size.width
            ArtworkView(url: player.currentTrack?.artworkUrl, size: size)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: AppTheme.shadowStrong, radius: 30, y: 12)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.name ?? "—")
                    .font(AppTheme.text(22, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Text(player.currentTrack?.artistName ?? "")
                    .font(AppTheme.text(15))
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                if let t = player.currentTrack {
                    LikesStore.shared.toggle(trackId: t.id)
                    isLiked.toggle()
                }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.leading, 12)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 12)
    }

    private var slider: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubTarget ?? player.position },
                    set: { scrubTarget = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing, let t = scrubTarget {
                        player.seek(to: t)
                        scrubTarget = nil
                    }
                }
            )
            .tint(AppTheme.ink)

            HStack {
                Text(format(scrubTarget ?? player.position))
                Spacer()
                Text(format(player.duration))
            }
            .font(AppTheme.text(11))
            .foregroundStyle(AppTheme.ink2)
        }
    }

    private var transport: some View {
        HStack {
            Button { queue.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(queue.shuffleOn ? AppTheme.ink : AppTheme.ink2)
            }.buttonStyle(.plain)
            Spacer()
            Button { Task { await queue.previous() } } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }.buttonStyle(.plain)
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(Color.white)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.black)
                }
                .frame(width: 64, height: 64)
            }.buttonStyle(.plain)
            Spacer()
            Button { Task { await queue.advance(manual: true) } } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
            }.buttonStyle(.plain)
            Spacer()
            Button { queue.cycleRepeatMode() } label: {
                Image(systemName: repeatIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(queue.repeatMode == .off ? AppTheme.ink2 : AppTheme.ink)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 16)
    }

    private var repeatIcon: String {
        switch queue.repeatMode {
        case .off: return "repeat"
        case .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    private func format(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
```

- [ ] **Step 13.3: Verify preserved symbols**

If the current codebase doesn't have `LikesStore.shared.isLiked(_:)` / `.toggle(trackId:)`, either:
(a) look up the actual like/unlike API in the original NowPlayingView and use that, or
(b) remove the heart toggle temporarily (leave `Image(systemName: "heart")` static) and flag it as a follow-up.

- [ ] **Step 13.4: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'NowPlayingView.swift.*error' | head -20`

Expected: no lines output.

### Task 14: Rewrite `QueueView.swift`

**Files:**
- Modify: `ios/SpotifyFree/Views/QueueView.swift` (full rewrite, ~204 → ~170 lines)

- [ ] **Step 14.1: Replace contents with:**

```swift
import SwiftUI

/// Sleek dark queue modal:
///   • Chevron-down header + "Queue" title
///   • "NOW PLAYING" card
///   • "NEXT UP" draggable list with always-visible grip handles
struct QueueView: View {
    @EnvironmentObject var queue: QueueManager
    var onDismiss: () -> Void = {}

    var body: some View {
        ZStack {
            AppTheme.fullPlayerBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                List {
                    if queue.currentIndex >= 0, queue.queue.indices.contains(queue.currentIndex) {
                        Section {
                            nowPlayingCard(queue.queue[queue.currentIndex].track)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        } header: {
                            sectionLabel("NOW PLAYING")
                        }
                    }

                    if queue.currentIndex + 1 < queue.queue.count {
                        Section {
                            ForEach(Array(queue.queue.enumerated()).filter { $0.offset > queue.currentIndex }, id: \.element.id) { pair in
                                upcomingRow(pair.element.track)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onMove(perform: handleMove)
                            .onDelete(perform: handleDelete)
                        } header: {
                            sectionLabel("NEXT UP")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text("Queue")
                .font(AppTheme.text(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .background(AppTheme.fullPlayerBg.frame(height: 0))
    }

    // MARK: Rows

    private func nowPlayingCard(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkUrl, size: 52)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(track.artistName)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func upcomingRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkUrl, size: 44)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.text(11, weight: .semibold))
            .foregroundStyle(AppTheme.ink2)
            .tracking(1.0)
            .padding(.top, 16)
    }

    // MARK: Mutations

    private func handleMove(from source: IndexSet, to destination: Int) {
        // Offsets are relative to the filtered "next up" slice. Translate to absolute.
        let startAbs = queue.currentIndex + 1
        let absSource = IndexSet(source.map { $0 + startAbs })
        let absDestination = destination + startAbs
        queue.move(from: absSource, to: absDestination)
    }

    private func handleDelete(at offsets: IndexSet) {
        let startAbs = queue.currentIndex + 1
        let absOffsets = IndexSet(offsets.map { $0 + startAbs })
        queue.remove(atOffsets: absOffsets)
    }
}
```

- [ ] **Step 14.2: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'QueueView.swift.*error' | head -10`

Expected: no lines output.

---

## Phase 6 — Detail Views (restyle only)

### Task 15: Restyle `ArtistDetailView.swift` for dark

**Files:**
- Modify: `ios/SpotifyFree/Views/ArtistDetailView.swift` (token swap only, no layout rewrite)

- [ ] **Step 15.1: Read and identify cozy token uses**

Run: `Read` on `ios/SpotifyFree/Views/ArtistDetailView.swift`. List every reference to: `AppTheme.background`, `AppTheme.surface`, `AppTheme.accent`, `AppTheme.accentTint`, `AppTheme.text`, `AppTheme.ink`, `AppTheme.ink2`, `AppTheme.ink3`, `AppTheme.display*`, `AppTheme.serif(…)`, `AppTheme.text(…)`, `CozyTopBar`, `CozySurface`, `CozyPrimaryButton`, `.appBackground()`.

- [ ] **Step 15.2: Replace cozy primitives + serif fonts**

Apply these edits across the file:
- `CozyTopBar(…)` → inline `Text(title).font(AppTheme.text(24, weight: .bold)).foregroundStyle(AppTheme.ink).padding(.horizontal, 16)`
- `CozySurface { … }` → wrapping `VStack`/content directly with `.background(AppTheme.surface).clipShape(RoundedRectangle(cornerRadius: 10))`
- `CozyPrimaryButton(…)` → `Button(action: …) { Text(title).font(AppTheme.text(14, weight: .semibold)).foregroundStyle(.black).padding(.horizontal, 24).padding(.vertical, 10).background(Color.white).clipShape(Capsule()) }.buttonStyle(.plain)`
- `AppTheme.display(N)` → `AppTheme.text(N, weight: .bold)`
- `AppTheme.serif(N, weight: .x)` → `AppTheme.text(N, weight: .x)`
- `.appBackground()` → `.background(AppTheme.bg.ignoresSafeArea())`

Hero tile: confirm size remains **240pt** (from prior polish pass); if it reverted, set back to 240.

Foreground colors: any `AppTheme.text` remains `.ink`, `AppTheme.textSecondary` / `.ink2` already correct (tokens now resolve to dark palette values).

- [ ] **Step 15.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'ArtistDetailView.swift.*error' | head -10`

Expected: no lines output.

### Task 16: Restyle `AlbumDetailView.swift` for dark

**Files:**
- Modify: `ios/SpotifyFree/Views/AlbumDetailView.swift`

- [ ] **Step 16.1: Apply the same transformations as Task 15.2**

Same edit passes: remove `Cozy*` primitives, replace `display`/`serif` font helpers with `text(_:weight:)`, swap `.appBackground()` for `AppTheme.bg.ignoresSafeArea()` background. Keep hero art at 240pt.

- [ ] **Step 16.2: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'AlbumDetailView.swift.*error' | head -10`

Expected: no lines output.

### Task 17: Restyle `PlaylistDetailView.swift` for dark

**Files:**
- Modify: `ios/SpotifyFree/Views/PlaylistDetailView.swift`

- [ ] **Step 17.1: Apply the same transformations as Task 15.2**

Same edit passes. Keep the existing edit/reorder functionality intact.

- [ ] **Step 17.2: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep 'PlaylistDetailView.swift.*error' | head -10`

Expected: no lines output.

### Task 18: Restyle any `LikedTracksView.swift` (if it exists) for dark

**Files:**
- Modify (if exists): `ios/SpotifyFree/Views/LikedTracksView.swift` or equivalent

- [ ] **Step 18.1: Locate the liked-songs view**

Run: `Grep` pattern `LikedTrack|Liked Songs|LikedTracksView|LikedSongsView` with `type: "swift"`, `output_mode: "files_with_matches"`.

- [ ] **Step 18.2: Apply the Task 15.2 transformation pass**

If the liked-songs listing is inline in `LibraryView.swift` pre-rewrite and wasn't preserved, you may need to create `Views/LikedTracksView.swift` from scratch using this template:

```swift
import SwiftUI

struct LikedTracksView: View {
    @EnvironmentObject var queue: QueueManager
    @FetchRequest(entity: LikedTrackEntity.entity(),
                  sortDescriptors: [NSSortDescriptor(keyPath: \LikedTrackEntity.likedAt, ascending: false)])
    private var liked: FetchedResults<LikedTrackEntity>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(liked) { row in
                    if let track = row.toTrack() {
                        TrackRow(track: track, onTap: { Task { await queue.playNow([track]) } },
                                 onAddToQueue: { queue.addToQueue(track) })
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.top, 8)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("Liked Songs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

Adapt `LikedTrackEntity.toTrack()` to whatever conversion the project already has (search the codebase first). If the attribute names or conversion are different, fix inline.

- [ ] **Step 18.3: Compile check**

Run: `cd /Users/sanikakapoor/Emulator/spotify-free/ios && xcodebuild … build 2>&1 | grep -E '(LikedTracks|Liked).*error' | head -10`

Expected: no lines output.

---

## Phase 7 — Final verification

### Task 19: Full clean build + URL preservation check

**Files:** none (verification only)

- [ ] **Step 19.1: Regenerate + clean build**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  xcodegen generate && \
  xcodebuild -project SpotifyFree.xcodeproj -scheme SpotifyFree \
    -destination 'generic/platform=iOS Simulator' -configuration Debug clean build 2>&1 | tail -30
```

Expected: `** BUILD SUCCEEDED **` with 0 errors, 0 warnings.

- [ ] **Step 19.2: Verify backend URL preserved in Info.plist**

Run:
```bash
grep -A1 SPOTIFY_FREE_BACKEND_URL /Users/sanikakapoor/Emulator/spotify-free/ios/SpotifyFree/Info.plist
```

Expected output contains `<string>$(SPOTIFY_FREE_BACKEND_URL)</string>`. **If missing, do NOT ship — fix `project.yml` first.**

- [ ] **Step 19.3: Verify no cozy primitives remain**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  grep -rn 'CozyTopBar\|CozySurface\|CozyPrimaryButton\|PillTabBar\|TintBackground' SpotifyFree/ 2>&1
```

Expected: no output (empty result). If any references remain, fix them.

- [ ] **Step 19.4: Verify no serif references remain**

Run:
```bash
cd /Users/sanikakapoor/Emulator/spotify-free/ios && \
  grep -rn 'DMSerifDisplay\|Manrope' SpotifyFree/ 2>&1
```

Expected: references may remain *only* in `FontLoader.swift` (font loader still loads bundled TTFs, harmless) and as a comment. No `AppTheme.display(` or `AppTheme.serif(` call site references besides definitions.

- [ ] **Step 19.5: Visual smoke on device/simulator**

Install, then verify:
1. App launches to black background, white text, no cream anywhere.
2. Home: greeting reflects time of day; if user has played tracks previously, "Recently Played" carousel appears; "Your Playlists" carousel appears if playlists exist.
3. Tab bar: Home/Search/Library/Queue, flush at bottom, active = white, inactive = gray.
4. Tap Queue tab → Queue modal slides up (fullScreenCover).
5. Search: empty → "Recent Searches" list; type text → white pill + dark results grouped by Songs/Albums/Artists.
6. Library: 2 gradient tiles (purple Liked, blue My Playlists); counts match CoreData; tapping a tile opens the corresponding list.
7. Play a track → MiniPlayer appears above tab bar as floating rounded card; thin white progress line animates; tap → FullPlayer.
8. FullPlayer: gradient bg, edge-to-edge album art, big white circular play button, heart toggle, slider scrubs + releases without stalling timer.
9. Queue modal: drag handles visible on all "Next Up" rows; drag reorders; swipe-delete works.
10. Artist/Album detail accessible from search results; dark palette; top tracks list functional; back chevron white.
11. Lock screen / Control Center: title/artist/artwork appear; play/pause/next/prev work.

If any item fails: return to the corresponding Phase's task and fix.

---

## Self-Review Summary

**Spec coverage:**
- All 11 numbered decisions from spec Decisions section → each implemented in a named task
- All 18 files in File Inventory → covered by Tasks 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18
- Design tokens → Task 1
- New RecentPlaysStore → Tasks 8–9
- Cozy primitives deletion → Task 2
- Backend URL preservation → Task 19.2
- Smoke verification → Task 19.5 (maps to spec §Verification items 1–12)

**No placeholders verified:** every code step contains concrete Swift code. Step 11.2 notes the one place where runtime state names may need adjustment against the current file; the exact edits are spelled out.

**Type consistency:** `MiniPlayerCard`, `FullPlayerView`, `QueueView`, `SleekTabBar`, `RootShell`, `RecentPlaysStore`, `PlaylistsIndexView`, `LikedTracksView` used consistently. `TrackRow` signature preserved from Task 6 across Task 10/11/18 call sites. `AppTheme.bg` / `.surface` / `.ink` / `.ink2` used uniformly.

**Adaptations needed at execution time:**
- Task 10: confirm CoreData `PlaylistEntity` attribute names (`createdAt`, `name`, `tracks`, `coverUrl`).
- Task 11: confirm existing `Album` / `Artist` model property names before plugging into rows.
- Task 13: confirm `LikesStore` API; if absent, stub the heart toggle.
- Task 18: confirm `LikedTrackEntity.toTrack()` or inline the conversion.

These are highlighted inline; not enough to warrant restructuring the plan.
