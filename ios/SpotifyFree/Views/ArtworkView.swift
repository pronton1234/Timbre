import SwiftUI

/// Thin async-image wrapper with a stable size and rounded corners.
///
/// Success path: real iTunes artwork via `AsyncImage` (its URLCache is fine
/// for v1). Failure / missing URL: a deterministic `ArtTile` gradient so the
/// UI stays cozy and non-empty. The seed is the url's `lastPathComponent`
/// or an explicit `seed` supplied by the caller (track/album/playlist id).
struct ArtworkView: View {
    let url: URL?
    let size: CGFloat
    var seedOverride: Int? = nil

    var body: some View {
        let seed = seedOverride ?? ArtworkView.seed(for: url)
        let radius = ArtTile.defaultCornerRadius(for: size)

        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        ArtTile(seed: seed, size: size, cornerRadius: radius)
                    }
                }
            } else {
                ArtTile(seed: seed, size: size, cornerRadius: radius)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    static func seed(for url: URL?) -> Int {
        if let url {
            return ArtTile.seed(from: url.lastPathComponent)
        }
        return 0
    }
}
