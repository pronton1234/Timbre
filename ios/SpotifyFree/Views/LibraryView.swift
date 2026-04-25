import SwiftUI
import CoreData

/// Sleek dark Library:
///   • H1 "Your Library"
///   • Row of 2 gradient category tiles (Liked Songs purple, My Playlists blue)
///   • Section "Playlists" — vertical list of real playlists
struct LibraryView: View {
    @EnvironmentObject var queue: QueueManager

    @FetchRequest(
        entity: PlaylistEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaylistEntity.createdAt, ascending: false)]
    ) private var playlists: FetchedResults<PlaylistEntity>

    @FetchRequest(
        entity: LikedTrackEntity.entity(),
        sortDescriptors: []
    ) private var liked: FetchedResults<LikedTrackEntity>

    @State private var showLiked = false
    @State private var showNewPlaylistSheet = false
    @State private var newPlaylistName: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Your Library")
                            .font(AppTheme.text(30, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Button { showNewPlaylistSheet = true } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 48)

                    HStack(spacing: 12) {
                        categoryTile(
                            gradient: AppTheme.likedGradient,
                            icon: "heart.fill",
                            title: "Liked Songs",
                            count: "\(liked.count) \(liked.count == 1 ? "song" : "songs")",
                            onTap: { showLiked = true }
                        )
                        NavigationLink {
                            PlaylistsIndexView()
                        } label: {
                            categoryTile(
                                gradient: AppTheme.playlistGradient,
                                icon: "music.note.list",
                                title: "My Playlists",
                                count: "\(playlists.count) \(playlists.count == 1 ? "playlist" : "playlists")",
                                onTap: {}
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)

                    if !playlists.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Playlists")
                                    .font(AppTheme.text(20, weight: .bold))
                                    .foregroundStyle(AppTheme.ink)
                                Spacer()
                            }
                            .padding(.horizontal, 16)

                            VStack(spacing: 0) {
                                ForEach(playlists) { pl in
                                    NavigationLink { PlaylistDetailView(playlist: pl) } label: {
                                        playlistRow(pl)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Color.clear.frame(height: 160)
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showLiked) {
                NavigationStack { LikedTracksView() }
            }
            .sheet(isPresented: $showNewPlaylistSheet) { newPlaylistSheet }
        }
    }

    // MARK: - Tiles

    private func categoryTile(
        gradient: LinearGradient,
        icon: String,
        title: String,
        count: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(alignment: .leading) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.text(14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(count)
                        .font(AppTheme.text(11))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 96)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func playlistRow(_ pl: PlaylistEntity) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: pl.coverArtURL, size: 56, seedOverride: ArtTile.seed(from: pl.id?.uuidString ?? (pl.name ?? "p")))
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(pl.name ?? "Untitled")
                    .font(AppTheme.text(15, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text("\(pl.tracks?.count ?? 0) songs")
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - New playlist sheet

    private var newPlaylistSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $newPlaylistName)
            }
            .navigationTitle("New Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showNewPlaylistSheet = false; newPlaylistName = "" }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            PersistenceController.shared.createPlaylist(name: name)
                        }
                        newPlaylistName = ""
                        showNewPlaylistSheet = false
                    }
                }
            }
        }
    }
}

/// Full-width list of all user playlists, opened from the "My Playlists"
/// gradient tile.
struct PlaylistsIndexView: View {
    @FetchRequest(
        entity: PlaylistEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \PlaylistEntity.createdAt, ascending: false)]
    ) private var playlists: FetchedResults<PlaylistEntity>

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(playlists) { pl in
                    NavigationLink { PlaylistDetailView(playlist: pl) } label: {
                        HStack(spacing: 12) {
                            ArtworkView(url: pl.coverArtURL, size: 56, seedOverride: ArtTile.seed(from: pl.id?.uuidString ?? (pl.name ?? "p")))
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pl.name ?? "Untitled")
                                    .font(AppTheme.text(15, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)
                                Text("\(pl.tracks?.count ?? 0) songs")
                                    .font(AppTheme.text(12))
                                    .foregroundStyle(AppTheme.ink2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 16)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("My Playlists")
        .navigationBarTitleDisplayMode(.inline)
    }
}
