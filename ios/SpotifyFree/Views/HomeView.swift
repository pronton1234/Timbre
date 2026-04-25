import SwiftUI

/// Sleek dark Home screen:
///   • Time-based greeting H1 (30pt bold white)
///   • "Recently Played" — horizontal scroll of 144pt art tiles, from RecentPlaysStore
///   • "Your Playlists" — horizontal scroll of 144pt tiles, from CoreData Playlists
struct HomeView: View {
    @EnvironmentObject var queue: QueueManager
    @EnvironmentObject var router: TabRouter
    @StateObject private var recents = RecentPlaysStore.shared

    @FetchRequest(
        entity: PlaylistEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaylistEntity.createdAt, ascending: false)]
    ) private var playlists: FetchedResults<PlaylistEntity>

    var body: some View {
        NavigationStack {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(greeting)
                    .font(AppTheme.text(30, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.top, 48)

                if !recents.items.isEmpty {
                    section(title: "Recently Played") {
                        ForEach(recents.items) { track in
                            carouselTile(
                                artworkUrl: track.artworkUrl,
                                title: track.name,
                                subtitle: track.artistName,
                                onTap: { Task { await queue.playNow([track]) } }
                            )
                        }
                    }
                }

                if !playlists.isEmpty {
                    section(title: "Your Playlists") {
                        ForEach(playlists) { pl in
                            NavigationLink {
                                PlaylistDetailView(playlist: pl)
                            } label: {
                                carouselTile(
                                    artworkUrl: pl.coverArtURL,
                                    title: pl.name ?? "Untitled",
                                    subtitle: "\(pl.tracks?.count ?? 0) songs",
                                    onTap: {}
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Color.clear.frame(height: 32)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.bg.ignoresSafeArea())
    }

    // MARK: - Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<18: return "Good afternoon"
        default:      return "Good evening"
        }
    }

    // MARK: - Section / Tile helpers

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.text(20, weight: .bold))
                .foregroundStyle(AppTheme.ink)
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    content()
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func carouselTile(
        artworkUrl: URL?,
        title: String,
        subtitle: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ArtworkView(url: artworkUrl, size: 144)
                    .frame(width: 144, height: 144)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
            }
            .frame(width: 144, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
