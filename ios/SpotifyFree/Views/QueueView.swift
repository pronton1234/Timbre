import SwiftUI

// MARK: - Animated Equalizer

private struct AnimatedEqualizer: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    let fraction: Double = isPlaying
                        ? 0.4 + 0.6 * abs(sin(t * 4 + Double(i) * 0.7))
                        : 0.25
                    Capsule()
                        .fill(color)
                        .frame(width: 3)
                        .frame(height: 20 * fraction, alignment: .bottom)
                        .animation(.easeInOut(duration: 0.12), value: fraction)
                }
            }
            .frame(width: 22, height: 20, alignment: .bottom)
        }
    }
}

// MARK: - QueueView

struct QueueView: View {
    @EnvironmentObject var queue: QueueManager
    @EnvironmentObject var player: AudioPlayer

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                Text("UP NEXT")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(2)
                    .foregroundStyle(Color.mmMutedFg)
                    .padding(.bottom, 4)

                Text("Queue")
                    .font(.display(40))
                    .foregroundStyle(Color.mmForeground)
                    .padding(.bottom, 32)

                // Now Playing
                if queue.currentIndex >= 0, queue.queue.indices.contains(queue.currentIndex) {
                    Text("NOW PLAYING")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(Color.mmMutedFg)
                        .padding(.bottom, 12)

                    let nowTrack = queue.queue[queue.currentIndex].track
                    HStack(spacing: 12) {
                        ArtworkView(url: nowTrack.artworkUrl, size: 56)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(nowTrack.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.mmBackground)
                                .lineLimit(1)
                            Text(nowTrack.artistName)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.mmBackground.opacity(0.6))
                                .lineLimit(1)
                        }

                        Spacer()

                        AnimatedEqualizer(isPlaying: player.isPlaying, color: Color.mmBackground)
                    }
                    .padding(12)
                    .background(Color.mmForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 32)
                }

                // Next in Queue
                let upcoming = queue.queue.enumerated().filter { $0.offset > queue.currentIndex }
                if !upcoming.isEmpty {
                    Text("NEXT IN QUEUE")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(Color.mmMutedFg)
                        .padding(.bottom, 12)

                    VStack(spacing: 4) {
                        ForEach(Array(upcoming), id: \.element.id) { (offset, item) in
                            queueRow(item.track, displayIndex: offset - queue.currentIndex)
                        }
                    }
                }

                if queue.queue.isEmpty {
                    Text("Your queue is empty.")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.mmMutedFg)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 64)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
            .padding(.bottom, 160)
        }
        .background(Color.clear)
    }

    private func queueRow(_ track: Track, displayIndex: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(displayIndex)")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Color.mmMutedFg)
                .frame(width: 20, alignment: .center)

            ArtworkView(url: track.artworkUrl, size: 44)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.mmForeground)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mmMutedFg)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatDuration(track.durationMs))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Color.mmMutedFg)
        }
        .padding(8)
    }

    private func formatDuration(_ ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let total = ms / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
