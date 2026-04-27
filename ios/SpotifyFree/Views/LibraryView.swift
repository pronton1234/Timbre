import SwiftUI
import CoreData

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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    Text("Your Library")
                        .font(.display(40))
                        .foregroundStyle(Color.mmForeground)
                        .padding(.bottom, 32)

                    // Liked Songs
                    Button { showLiked = true } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(
                                        colors: [Color.mmAccent.opacity(0.8), Color.mmAccent.opacity(0.4)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.mmBackground)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Liked Songs")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color.mmForeground)
                                Text("\(liked.count) \(liked.count == 1 ? "song" : "songs")")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.mmMutedFg)
                            }
                            Spacer()
                        }
                        .padding(8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 32)

                    // Playlists
                    if !playlists.isEmpty {
                        HStack {
                            Text("PLAYLISTS")
                                .font(.system(size: 11, weight: .regular))
                                .tracking(2)
                                .foregroundStyle(Color.mmMutedFg)
                            Spacer()
                            Button { showNewPlaylistSheet = true } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.mmMutedFg)
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 12)

                        VStack(spacing: 4) {
                            ForEach(playlists) { pl in
                                NavigationLink { PlaylistDetailView(playlist: pl) } label: {
                                    playlistRow(pl)
                                }.buttonStyle(.plain)
                            }
                        }
                    } else {
                        Button { showNewPlaylistSheet = true } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.mmSurface)
                                        .frame(width: 48, height: 48)
                                    Image(systemName: "plus")
                                        .font(.system(size: 20))
                                        .foregroundStyle(Color.mmMutedFg)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("New Playlist")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Color.mmForeground)
                                    Text("Create your first playlist")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.mmMutedFg)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 56)
                .padding(.bottom, 160)
            }
            .background(Color.clear)
            .navigationBarHidden(true)
            .sheet(isPresented: $showLiked) {
                NavigationStack { LikedTracksView() }
            }
            .sheet(isPresented: $showNewPlaylistSheet) { newPlaylistSheet }
        }
    }

    private func playlistRow(_ pl: PlaylistEntity) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: pl.coverArtURL, size: 48, seedOverride: ArtTile.seed(from: pl.id?.uuidString ?? (pl.name ?? "p")))
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(pl.name ?? "Untitled")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.mmForeground)
                    .lineLimit(1)
                Text("Playlist · \(pl.tracks?.count ?? 0) tracks")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mmMutedFg)
            }
            Spacer()
        }
        .padding(8)
        .contentShape(Rectangle())
    }

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
                        if !name.isEmpty { PersistenceController.shared.createPlaylist(name: name) }
                        newPlaylistName = ""
                        showNewPlaylistSheet = false
                    }
                }
            }
        }
    }
}
