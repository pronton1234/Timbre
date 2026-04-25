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
