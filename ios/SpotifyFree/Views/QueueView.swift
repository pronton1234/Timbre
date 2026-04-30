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
                if let nowTrack = queue.currentTrack {
                    Text("NOW PLAYING")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(Color.mmMutedFg)
                        .padding(.bottom, 12)

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

                // User Queue — drag-to-reorder
                if !queue.userQueue.isEmpty {
                    Text("NEXT IN QUEUE")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(Color.mmMutedFg)
                        .padding(.bottom, 12)

                    List {
                        ForEach(queue.userQueue) { item in
                            queueRow(item.track, badge: nil)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        }
                        .onMove { source, dest in queue.move(from: source, to: dest) }
                        .onDelete { offsets in queue.remove(atOffsets: offsets) }
                    }
                    .listStyle(.plain)
                    .scrollDisabled(true)
                    .environment(\.editMode, .constant(.active))
                    .frame(minHeight: CGFloat(queue.userQueue.count * 64))
                    .padding(.bottom, 24)
                }

                // Context remaining — tappable but not reorderable
                if let ctx = queue.context, !ctx.remainingTracks.isEmpty {
                    Text("NEXT FROM \(ctx.contextLabel.uppercased())")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(2)
                        .foregroundStyle(Color.mmMutedFg)
                        .padding(.bottom, 12)
                        .lineLimit(1)

                    let remaining = ctx.remainingTracks
                    VStack(spacing: 4) {
                        ForEach(Array(remaining.enumerated()), id: \.element.id) { i, track in
                            queueRow(track, badge: nil)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    Task { await queue.jumpContext(to: ctx.cursor + 1 + i) }
                                }
                        }
                    }
                    .padding(.bottom, 24)
                }

                if queue.currentTrack == nil && queue.userQueue.isEmpty {
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

    private func queueRow(_ track: Track, badge: String?) -> some View {
        HStack(spacing: 12) {
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

            if let badge {
                Text(badge)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.mmMutedFg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.mmSurface)
                    .clipShape(Capsule())
            } else {
                Text(formatDuration(track.durationMs))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.mmMutedFg)
            }
        }
        .padding(8)
    }

    private func formatDuration(_ ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let total = ms / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
