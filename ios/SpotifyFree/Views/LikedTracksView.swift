import SwiftUI
import CoreData

struct LikedTracksView: View {
    @EnvironmentObject var queue: QueueManager
    @FetchRequest(
        entity: LikedTrackEntity.entity(),
        sortDescriptors: [NSSortDescriptor(key: "addedAt", ascending: false)]
    ) private var liked: FetchedResults<LikedTrackEntity>

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(liked, id: \.objectID) { row in
                    let track = row.asTrack
                    TrackRow(
                        track: track,
                        onTap: { Task { await queue.playNow([track]) } },
                        onAddToQueue: { queue.addToQueue(track) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 8)
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle("Liked Songs")
        .navigationBarTitleDisplayMode(.inline)
    }
}
