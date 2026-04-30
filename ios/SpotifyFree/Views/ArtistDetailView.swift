import SwiftUI

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(\.dismiss) private var dismiss

    @State private var albums: [Album] = []
    @State private var popular: [Track] = []
    @State private var following: Bool = false

    private var seed: Int { ArtTile.seed(from: artist.itunesArtistId) }

    private var heroArtworkURL: URL? {
        albums.first?.artworkUrl
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                hero
                titleBlock
                actionRow
                popularSection
                albumsSection

                Spacer(minLength: 120)
            }
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationBarHidden(true)
        .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
        .task {
            await load()
        }
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("ARTIST")
                .font(AppTheme.text(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppTheme.ink3)
            Spacer()
            // Invisible spacer to balance the back chip so the kicker stays centered.
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var hero: some View {
        ArtworkView(url: heroArtworkURL, size: 240, seedOverride: seed)
            .shadow(color: AppTheme.shadowStrong, radius: 30, x: 0, y: 14)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(artist.name)
                .font(AppTheme.display(36))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let g = artist.primaryGenre, !g.isEmpty {
                Text(g)
                    .font(AppTheme.text(13))
                    .foregroundStyle(AppTheme.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                let ts = popular
                guard !ts.isEmpty else { return }
                Task { await QueueManager.shared.playNow(ts, kind: .artistTopTracks(artist)) }
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
                following.toggle()
            } label: {
                Text(following ? "Following" : "Follow")
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(following ? Color.mmBackground : Color.mmForeground)
                    .frame(height: 48)
                    .padding(.horizontal, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(following ? AppTheme.ink : AppTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(following ? Color.clear : AppTheme.hair, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var popularSection: some View {
        if !popular.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("POPULAR")
                    .font(AppTheme.text(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppTheme.ink2)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    let tops = Array(popular.prefix(5).enumerated())
                    ForEach(tops, id: \.element.id) { pair in
                        let (idx, track) = pair
                        TrackRow(
                            track: track,
                            index: idx + 1,
                            onTap: {
                                Task { await QueueManager.shared.playNow(popular, startAt: idx, kind: .artistTopTracks(artist)) }
                            },
                            onAddToQueue: { QueueManager.shared.addToQueue(track) }
                        )
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        if idx < tops.count - 1 {
                            Rectangle()
                                .fill(AppTheme.hair)
                                .frame(height: 0.5)
                                .padding(.leading, 60)
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

    @ViewBuilder
    private var albumsSection: some View {
        if !albums.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("ALBUMS")
                    .font(AppTheme.text(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppTheme.ink2)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(albums, id: \.id) { album in
                            NavigationLink(value: album) {
                                albumTile(album)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    private func albumTile(_ album: Album) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: album.artworkUrl, size: 140)
            Text(album.name)
                .font(AppTheme.text(14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            if let y = album.releaseDate.map({ Self.yearFormatter.string(from: $0) }) {
                Text(y)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink3)
            }
        }
        .frame(width: 140, alignment: .leading)
    }

    // MARK: - Data

    private func load() async {
        // Fetch albums and Last.fm-ranked top tracks in parallel.
        async let fetchedAlbums = (try? await iTunesClient.shared.albumsByArtist(artist.itunesArtistId)) ?? []
        async let fetchedPopular = SearchService.shared.artistTopTracks(name: artist.name, artistId: artist.itunesArtistId)
        let (albums, popular) = await (fetchedAlbums, fetchedPopular)
        await MainActor.run {
            self.albums = albums
            // Use Last.fm results if non-empty, otherwise fall back to first album tracks.
            if !popular.isEmpty {
                self.popular = popular
            }
        }
        // If Last.fm returned nothing and we have albums, fall back to first album tracks.
        if popular.isEmpty, let top = albums.first {
            do {
                let ts = try await iTunesClient.shared.tracksByAlbum(top.itunesCollectionId)
                await MainActor.run { self.popular = ts }
            } catch {
                print("ArtistDetailView.load fallback failed: \(error)")
            }
        }
    }

    private static let yearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy"
        return f
    }()
}
