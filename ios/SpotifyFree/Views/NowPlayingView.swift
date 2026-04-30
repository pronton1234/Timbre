import SwiftUI
import MediaPlayer
import UIKit

// MARK: - MiniPlayerCard

struct MiniPlayerCard: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var queue: QueueManager
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.mmForeground.opacity(0.10))
                    Rectangle()
                        .fill(Color.mmForeground.opacity(0.7))
                        .frame(width: geo.size.width * (player.isPlaying ? 0.66 : 0.33))
                        .animation(.easeOut(duration: 0.4), value: player.isPlaying)
                }
            }
            .frame(height: 2)

            // Content
            HStack(spacing: 12) {
                ArtworkView(url: player.currentTrack?.artworkUrl, size: 44)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.name ?? "—")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.mmForeground)
                        .lineLimit(1)
                    Text(player.currentTrack?.artistName ?? "")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Color.mmForeground.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.mmForeground)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await queue.advance(manual: true) }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.mmForeground)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.mmPlayerBg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) else { return }  // horizontal swipe only
                    if dx < -50 {
                        Task { await queue.advance(manual: true) }
                    } else if dx > 50 {
                        Task { await queue.previous() }
                    }
                }
        )
    }
}

// MARK: - FullPlayerView

struct FullPlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var queue: QueueManager
    var onDismiss: () -> Void

    @State private var scrubTarget: Double? = nil
    @State private var isLiked = false
    @State private var lyrics: TrackLyrics? = nil
    @State private var lyricsLoading = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.mmSurface, Color.mmBackground],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)
                artwork
                Spacer(minLength: 16)
                titleBlock
                slider
                transport
                lyricsPanel
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
        }
        .onAppear { refreshLiked(); loadLyrics() }
        .onChange(of: player.currentTrack?.id) { _ in refreshLiked(); loadLyrics() }
    }

    private func refreshLiked() {
        if let t = player.currentTrack {
            isLiked = PersistenceController.shared.isLiked(t)
        } else {
            isLiked = false
        }
    }

    private func loadLyrics() {
        guard let track = player.currentTrack else { lyrics = nil; return }
        lyricsLoading = true
        Task {
            let result = await LyricsClient.shared.fetchLyrics(for: track)
            await MainActor.run { lyrics = result; lyricsLoading = false }
        }
    }

    private func toggleLike() {
        guard let t = player.currentTrack else { return }
        let next = !isLiked
        PersistenceController.shared.setLiked(t, liked: next)
        isLiked = next
    }

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.mmForeground)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text("Now Playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.mmForeground)
            Spacer()
            Menu {
                if player.currentTrack != nil {
                    Button { toggleLike() } label: {
                        Label(isLiked ? "Unlike" : "Like", systemImage: "heart")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.mmForeground)
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
                .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.currentTrack?.name ?? "—")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.mmForeground)
                    .lineLimit(2)
                // 5.3: tap artist name → ArtistDetailView
                if let track = player.currentTrack, let artistId = track.artistId {
                    NavigationLink(value: Artist(itunesArtistId: artistId, name: track.artistName, primaryGenre: nil, artistLinkUrl: nil)) {
                        Text(track.artistName)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.mmMutedFg)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(player.currentTrack?.artistName ?? "")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.mmMutedFg)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button { toggleLike() } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 24))
                    .foregroundStyle(isLiked ? Color.mmAccent : Color.mmForeground)
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
            .tint(Color.mmForeground)

            HStack {
                // 5.4: left = elapsed (counts up), right = remaining (counts down as -MM:SS)
                // 5.8: clamp elapsed to [0, duration] so display never goes out of bounds
                let elapsed = min(max(scrubTarget ?? player.position, 0), max(player.duration, 0))
                let remaining = max(player.duration - elapsed, 0)
                Text(format(elapsed))
                Spacer()
                Text("-" + format(remaining))
            }
            .font(.system(size: 11))
            .foregroundStyle(Color.mmMutedFg)
        }
    }

    private var transport: some View {
        HStack {
            Button { queue.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(queue.shuffleOn ? Color.mmAccent : Color.mmMutedFg)
            }.buttonStyle(.plain)
            Spacer()
            Button { Task { await queue.previous() } } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.mmForeground)
            }.buttonStyle(.plain)
            Spacer()
            Button { player.togglePlayPause() } label: {
                ZStack {
                    Circle().fill(Color.mmForeground)
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.mmBackground)
                }
                .frame(width: 64, height: 64)
            }.buttonStyle(.plain)
            Spacer()
            Button { Task { await queue.advance(manual: true) } } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.mmForeground)
            }.buttonStyle(.plain)
            Spacer()
            Button { queue.cycleRepeatMode() } label: {
                Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(queue.repeatMode == .off ? Color.mmMutedFg : Color.mmAccent)
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Lyrics panel (5.11)

    @ViewBuilder
    private var lyricsPanel: some View {
        if lyricsLoading {
            ProgressView()
                .tint(Color.mmMutedFg)
                .padding(.top, 24)
        } else if let lyr = lyrics {
            VStack(alignment: .leading, spacing: 0) {
                Text("LYRICS")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(2)
                    .foregroundStyle(Color.mmMutedFg)
                    .padding(.bottom, 12)
                    .padding(.top, 20)

                if lyr.hasSyncedLines {
                    // Synced lyrics: highlight current line
                    let pos = player.position
                    let currentIdx = lyr.lines.lastIndex { $0.timestamp <= pos } ?? 0
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(lyr.lines.enumerated()), id: \.element.id) { idx, line in
                                    Text(line.text.isEmpty ? "·" : line.text)
                                        .font(.system(size: idx == currentIdx ? 17 : 14, weight: idx == currentIdx ? .semibold : .regular))
                                        .foregroundStyle(idx == currentIdx ? Color.mmForeground : Color.mmMutedFg)
                                        .animation(.easeInOut(duration: 0.2), value: currentIdx)
                                        .id(idx)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                        .onChange(of: currentIdx) { idx in
                            withAnimation { proxy.scrollTo(idx, anchor: .center) }
                        }
                    }
                } else {
                    Text(lyr.plainText)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mmMutedFg)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func format(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
