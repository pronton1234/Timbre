import SwiftUI

/// Single track row — MinimalMusic style.
/// Optional leading index, 48×48 artwork, title/artist, trailing duration.
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
    }

    private func formatDuration(_ ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let total = ms / 1000
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
