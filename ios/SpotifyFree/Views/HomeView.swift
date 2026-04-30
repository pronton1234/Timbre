import SwiftUI

struct HomeView: View {
    @EnvironmentObject var queue: QueueManager
    @StateObject private var recents = RecentPlaysStore.shared

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WELCOME BACK")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(2)
                            .foregroundStyle(Color.mmMutedFg)

                        HStack(spacing: 0) {
                            Text("Your ")
                                .font(.display(44))
                                .foregroundStyle(Color.mmForeground)
                            Text("music")
                                .font(.display(44))
                                .italic()
                                .foregroundStyle(Color.mmForeground)
                            Text(".")
                                .font(.display(44))
                                .foregroundStyle(Color.mmForeground)
                        }
                    }
                    .padding(.bottom, 32)

                    if !recents.contexts.isEmpty {
                        Text("RECENTLY PLAYED")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(2)
                            .foregroundStyle(Color.mmMutedFg)
                            .padding(.bottom, 16)

                        // 2-column grid of context tiles
                        let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
                        LazyVGrid(columns: cols, spacing: 12) {
                            ForEach(recents.contexts) { ctx in
                                contextTile(ctx)
                            }
                        }
                    } else {
                        Text("Search for something to get started.")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.mmMutedFg)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 160)
            }
            .background(Color.clear)
            .navigationBarHidden(true)
            .navigationDestination(for: Album.self) { AlbumDetailView(album: $0) }
            .navigationDestination(for: Artist.self) { ArtistDetailView(artist: $0) }
            .navigationDestination(for: PlaylistEntity.self) { PlaylistDetailView(playlist: $0) }
        }
    }

    // MARK: - Context tile

    @ViewBuilder
    private func contextTile(_ ctx: RecentContext) -> some View {
        switch ctx.kind {
        case .album(let album):
            NavigationLink(value: album) {
                tileContent(title: ctx.title, subtitle: ctx.subtitle, artworkURL: ctx.artworkURL, isRound: false)
            }
            .buttonStyle(.plain)

        case .artistTopTracks(let artist):
            NavigationLink(value: artist) {
                tileContent(title: ctx.title, subtitle: ctx.subtitle, artworkURL: ctx.artworkURL, isRound: true)
            }
            .buttonStyle(.plain)

        case .playlist:
            // Playlist tiles tap to re-play — we don't have the PlaylistEntity here,
            // only the lightweight id+name. Show as a plain tile that fires playback.
            tileContent(title: ctx.title, subtitle: ctx.subtitle, artworkURL: ctx.artworkURL, isRound: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    // No detail view available without CoreData fetch; re-play nothing.
                    // When the user opens the Library tab they can navigate to the playlist.
                }

        case .search(let track):
            tileContent(title: ctx.title, subtitle: ctx.subtitle, artworkURL: ctx.artworkURL, isRound: false)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await queue.playNow([track]) }
                }
        }
    }

    private func tileContent(title: String, subtitle: String, artworkURL: URL?, isRound: Bool) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, size: 56)
                .frame(width: 56, height: 56)
                .clipShape(isRound ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.mmForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.mmMutedFg)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.mmSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
