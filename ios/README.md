# spotify-free iOS

SwiftUI iOS 16 app. Uses iTunes Search API for metadata and the local
`spotify-free-backend` for YouTube audio resolution.

## Generating the Xcode project

The repo does not check in `.xcodeproj` / `.xcworkspace` — instead we use
[XcodeGen](https://github.com/yonaskolb/XcodeGen) so the source of truth is
`project.yml`.

```bash
brew install xcodegen
cd ios
xcodegen            # produces SpotifyFree.xcodeproj
open SpotifyFree.xcodeproj
```

## First-run checklist (in Xcode)

1. Select the `SpotifyFree` target → Signing & Capabilities → set your Team.
2. Bundle identifier: change `com.spotifyfree.SpotifyFree` to one unique to your
   account (e.g. `com.<yourname>.spotifyfree`). Also update the
   `com.apple.developer.icloud-container-identifiers` entry in
   `SpotifyFree/Resources/SpotifyFree.entitlements` accordingly.
3. Capabilities → iCloud: enable CloudKit, pick the matching container.
4. Build setting `SPOTIFY_FREE_BACKEND_URL` → set to your backend URL
   (Debug: `http://localhost:3000`, Release: `https://<you>.duckdns.org`).
5. Deploy: Cmd+R on a physical device (background audio doesn't work on
   simulator).

## Running tests

Unit tests: `Cmd+U` or `xcodebuild test -scheme SpotifyFree`.

UI tests expect a running backend at the URL above. Start it with
`cd ../backend && npm start` before running the UI test target.

## Directory map

```
SpotifyFree/
├── App/SpotifyFreeApp.swift        # @main, audio session, remote-control bootstrap
├── Models/*.swift                  # Track, Album, Artist, Playlist, QueueItem, RepeatMode
├── Persistence/
│   ├── PersistenceController.swift # NSPersistentCloudKitContainer + CRUD helpers
│   └── SpotifyFree.xcdatamodeld/   # Playlist/LikedTrack/RecentlyPlayed entities
├── Services/
│   ├── iTunesClient.swift          # iTunes Search API (actor)
│   ├── BackendClient.swift         # /resolve /stream
│   ├── AudioPlayer.swift           # AVQueuePlayer + now-playing + remote commands
│   └── QueueManager.swift          # queue + shuffle + repeat + next-track prewarm
├── Views/*.swift                   # HomeView, SearchView, LibraryView, detail, NowPlaying, Queue, ArtworkView
└── Resources/
    ├── Info.plist
    └── SpotifyFree.entitlements
SpotifyFreeTests/                   # QueueManager, iTunesClient
SpotifyFreeUITests/                 # Search→play, playlist-persistence
```

## Latency design

- `QueueManager.startCurrent()` triggers `AudioPlayer.prewarm(nextTrack)` as
  soon as the current track starts. This both pre-resolves the next stream URL
  and inserts an `AVPlayerItem` into `AVQueuePlayer` so buffering begins
  immediately. Hitting **Next** then promotes the pre-warmed item — sub-300 ms.
- `AVPlayerItem.preferredForwardBufferDuration = 5` starts playback ~500 ms
  sooner than the default.
- `AVPlayer.automaticallyWaitsToMinimizeStalling = false` keeps startup latency
  low at the cost of being slightly more eager on jittery networks (we surface
  a buffering indicator via `isPlaybackBufferEmpty`).

## Stream-expiry recovery

YouTube's googlevideo URLs expire after ~6h. `AudioPlayer.handlePossibleStreamExpiry`
listens for `AVPlayerItem.failedToPlayToEndTimeNotification` + stall events.
When an item fails with codes `-11828`, `-11829`, `-1001`, `-1009`, we:

1. Save `player.currentTime()`
2. Call `BackendClient.refreshStream(videoId:)`
3. Replace the player item with the fresh URL
4. Seek back to the saved offset and resume

Users never see a failure — at worst a sub-second blip.
