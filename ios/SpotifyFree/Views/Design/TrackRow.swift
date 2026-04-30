import SwiftUI

/// Single track row — MinimalMusic style.
/// Optional leading index, 48×48 artwork, title/artist, trailing duration.
/// Swipe-left gesture: drag ≥30% of row width fills the background green and
/// adds the track to the queue on release. Shorter swipes spring back.
struct TrackRow: View {
    let track: Track
    var index: Int? = nil
    var showArtwork: Bool = true
    var onTap: () -> Void = {}
    var onAddToQueue: (() -> Void)? = nil
    var accessory: AnyView? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var queued = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                // Green fill proportional to drag distance (5.6)
                if onAddToQueue != nil {
                    let fillFraction = min(max(-dragOffset / geo.size.width, 0), 1)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.mmAccent.opacity(queued ? 1 : fillFraction * 0.85))
                    if fillFraction > 0 || queued {
                        HStack {
                            Spacer()
                            Image(systemName: queued ? "checkmark" : "text.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .opacity(min(fillFraction * 2, 1))
                                .padding(.trailing, 16)
                        }
                    }
                }

                // Row content, offset left as user drags
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        if let index {
                            Text("\(index)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Color.mmMutedFg)
                                .frame(width: 20, alignment: .center)
                        }
                        if showArtwork {
                            ArtworkView(url: track.artworkUrl, size: 48)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.mmForeground)
                                .lineLimit(1)
                            Text(track.artistName)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(Color.mmMutedFg)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if let accessory {
                            accessory
                        } else if let onAddToQueue {
                            Button(action: onAddToQueue) {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.mmMutedFg)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(formatDuration(track.durationMs))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(Color.mmMutedFg)
                        }
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color.mmBackground.opacity(0.001))  // needed for hit testing
                .offset(x: dragOffset)
                .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: dragOffset)
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard onAddToQueue != nil else { return }
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        dragOffset = min(0, value.translation.width)
                    }
                    .onEnded { value in
                        guard let onAddToQueue else {
                            dragOffset = 0
                            return
                        }
                        let threshold = geo.size.width * 0.3
                        if -dragOffset >= threshold {
                            onAddToQueue()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            queued = true
                            withAnimation(.easeOut(duration: 0.25)) { dragOffset = 0 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { queued = false }
                        } else {
                            withAnimation(.interactiveSpring()) { dragOffset = 0 }
                        }
                    }
            )
        }
        .frame(height: 64)
    }

    private func formatDuration(_ ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let total = ms / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
