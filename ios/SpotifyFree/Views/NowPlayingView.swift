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
        .onAppear { refreshLiked() }
        .onChange(of: player.currentTrack?.id) { _ in refreshLiked() }
    }

    private func refreshLiked() {
        if let t = player.currentTrack {
            isLiked = PersistenceController.shared.isLiked(t)
        } else {
            isLiked = false
        }
    }

    private func toggleLike() {
        guard let t = player.currentTrack else { return }
        let next = !isLiked
        PersistenceController.shared.setLiked(t, liked: next)
        isLiked = next
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
                if player.currentTrack != nil {
                    Button {
                        toggleLike()
                    } label: {
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
                toggleLike()
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
