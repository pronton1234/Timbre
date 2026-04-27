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

                    // Recently Played section
                    if !recents.items.isEmpty {
                        Text("RECENTLY PLAYED")
                            .font(.system(size: 11, weight: .regular))
                            .tracking(2)
                            .foregroundStyle(Color.mmMutedFg)
                            .padding(.bottom, 12)

                        VStack(spacing: 4) {
                            ForEach(recents.items) { track in
                                TrackRow(
                                    track: track,
                                    onTap: { Task { await queue.playNow([track]) } }
                                )
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
            .navigationDestination(for: PlaylistEntity.self) { PlaylistDetailView(playlist: $0) }
        }
    }
}
