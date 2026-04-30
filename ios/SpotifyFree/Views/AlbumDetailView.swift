import SwiftUI

struct AlbumDetailView: View {
    let album: Album
    @State private var tracks: [Track] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                hero
                actionRow
                trackList

                Spacer(minLength: 120)
            }
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationBarHidden(true)
        .task {
            do { tracks = try await iTunesClient.shared.tracksByAlbum(album.itunesCollectionId) }
            catch { print("tracksByAlbum failed: \(error)") }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer()
            Text("ALBUM")
                .font(AppTheme.text(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppTheme.ink3)
            Spacer()
            Button { } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ArtworkView(url: album.artworkUrl, size: 240,
                        seedOverride: ArtTile.seed(from: album.id))
                .shadow(color: AppTheme.shadowStrong, radius: 30, x: 0, y: 14)
            VStack(spacing: 4) {
                Text(album.name)
                    .font(AppTheme.display3)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(AppTheme.text(13))
                    .foregroundStyle(AppTheme.ink2)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private var subtitle: String {
        var parts = [album.artistName]
        if let d = album.releaseDate {
            let f = DateFormatter()
            f.dateFormat = "yyyy"
            parts.append(f.string(from: d))
        }
        return parts.joined(separator: " · ")
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                Task { await QueueManager.shared.playNow(tracks, kind: .album(album)) }
            } label: {
                Text("Play")
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(Color.mmBackground)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color.mmForeground)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Button {
                // Placeholder for album-like toggle; wired up when CoreData
                // liked-albums lands.
            } label: {
                Image(systemName: "heart")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(AppTheme.hair, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRACKS")
                .font(AppTheme.text(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppTheme.ink2)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { pair in
                    let (idx, t) = pair
                    TrackRow(
                        track: t,
                        index: idx + 1,
                        showArtwork: false,
                        onTap: { Task { await QueueManager.shared.playNow(tracks, startAt: idx, kind: .album(album)) } },
                        onAddToQueue: { QueueManager.shared.addToQueue(t) }
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    if idx < tracks.count - 1 {
                        Rectangle()
                            .fill(AppTheme.hair)
                            .frame(height: 0.5)
                            .padding(.leading, 40)
                    }
                }
            }
            .padding(8)
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
    }
}
