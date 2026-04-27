import SwiftUI
import MediaPlayer

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
    }
}

// MARK: - FullPlayerView

struct FullPlayerView: View {
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var queue: QueueManager
    var onDismiss: () -> Void

    @State private var scrubTarget: Double? = nil
    @State private var isLiked = false

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
                Text(player.currentTrack?.artistName ?? "")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.mmMutedFg)
                    .lineLimit(1)
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
                Text(format(scrubTarget ?? player.position))
                Spacer()
                Text(format(player.duration))
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

    private func format(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        let total = Int(s)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
