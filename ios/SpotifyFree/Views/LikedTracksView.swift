import SwiftUI
import CoreData

struct LikedTracksView: View {
    @EnvironmentObject var queue: QueueManager
    @FetchRequest(
        entity: LikedTrackEntity.entity(),
        sortDescriptors: [NSSortDescriptor(key: "addedAt", ascending: false)]
    ) private var liked: FetchedResults<LikedTrackEntity>

    var body: some View {
        List {
            ForEach(liked, id: \.objectID) { row in
                let track = row.asTrack
                TrackRow(
                    track: track,
                    onTap: { Task { await queue.playNow([track]) } },
                    onAddToQueue: { queue.addToQueue(track) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                // 5.7: swipe-to-unlike
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        PersistenceController.shared.setLiked(track, liked: false)
                    } label: {
                        Label("Unlike", systemImage: "heart.slash")
                    }
                    .tint(Color.mmAccent)
                }
            }
        }
        .listStyle(.plain)
        .background(Color.mmBackground.ignoresSafeArea())
        .navigationTitle("Liked Songs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
