import SwiftUI
import CoreData

struct PlaylistDetailView: View {
    @ObservedObject var playlist: PlaylistEntity
    @Environment(\.managedObjectContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    private var tracks: [PlaylistTrackEntity] {
        let all = (playlist.tracks as? Set<PlaylistTrackEntity>) ?? []
        return all.sorted { $0.position < $1.position }
    }

    private var seed: Int {
        ArtTile.seed(from: playlist.id?.uuidString ?? (playlist.name ?? "playlist"))
    }

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
            Text("PLAYLIST")
                .font(AppTheme.text(11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppTheme.ink3)
            Spacer()
            Menu {
                Button(role: .destructive) {
                    PersistenceController.shared.deletePlaylist(playlist)
                    dismiss()
                } label: { Label("Delete playlist", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AppTheme.surface))
                    .overlay(Circle().stroke(AppTheme.hair, lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ArtworkView(url: playlist.coverArtURL, size: 240, seedOverride: seed)
                .shadow(color: AppTheme.shadowStrong, radius: 30, x: 0, y: 14)
            VStack(spacing: 4) {
                Text(playlist.name ?? "Playlist")
                    .font(AppTheme.display3)
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Text("\(tracks.count) tracks")
                    .font(AppTheme.text(13))
                    .foregroundStyle(AppTheme.ink2)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                let ts = tracks.map(\.asTrack)
                Task { await QueueManager.shared.playNow(ts) }
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
                let ts = tracks.map(\.asTrack).shuffled()
                Task { await QueueManager.shared.playNow(ts) }
            } label: {
                Image(systemName: "shuffle")
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

    @ViewBuilder
    private var trackList: some View {
        if tracks.isEmpty {
            Text("This playlist is empty. Add tracks from search or an album.")
                .font(AppTheme.text(13))
                .foregroundStyle(AppTheme.ink2)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AppTheme.hair, lineWidth: 0.5)
                )
                .padding(.horizontal, 20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("TRACKS")
                    .font(AppTheme.text(11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppTheme.ink2)
                    .padding(.horizontal, 20)

                VStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.element.objectID) { pair in
                        let (idx, pt) = pair
                        let track = pt.asTrack
                        TrackRow(
                            track: track,
                            onTap: {
                                let ts = tracks.map(\.asTrack)
                                Task { await QueueManager.shared.playNow(ts, startAt: idx) }
                            },
                            onAddToQueue: { QueueManager.shared.addToQueue(track) }
                        )
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                ctx.delete(pt)
                                try? ctx.save()
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                        if idx < tracks.count - 1 {
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
}
