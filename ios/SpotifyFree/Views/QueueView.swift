import SwiftUI

/// Sleek dark queue modal:
///   • Chevron-down header + "Queue" title
///   • "NOW PLAYING" card
///   • "NEXT UP" draggable list with always-visible grip handles
struct QueueView: View {
    @EnvironmentObject var queue: QueueManager
    var onDismiss: () -> Void = {}

    var body: some View {
        ZStack {
            AppTheme.fullPlayerBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                List {
                    if queue.currentIndex >= 0, queue.queue.indices.contains(queue.currentIndex) {
                        Section {
                            nowPlayingCard(queue.queue[queue.currentIndex].track)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        } header: {
                            sectionLabel("NOW PLAYING")
                        }
                    }

                    if queue.currentIndex + 1 < queue.queue.count {
                        Section {
                            ForEach(Array(queue.queue.enumerated()).filter { $0.offset > queue.currentIndex }, id: \.element.id) { pair in
                                upcomingRow(pair.element.track)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                            .onMove(perform: handleMove)
                            .onDelete(perform: handleDelete)
                        } header: {
                            sectionLabel("NEXT UP")
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .frame(width: 40, height: 40)
            }
            Spacer()
            Text("Queue")
                .font(AppTheme.text(15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    // MARK: Rows

    private func nowPlayingCard(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkUrl, size: 52)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(track.artistName)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.surface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func upcomingRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            ArtworkView(url: track.artworkUrl, size: 44)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(AppTheme.text(14, weight: .semibold))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(1)
                Text(track.artistName)
                    .font(AppTheme.text(12))
                    .foregroundStyle(AppTheme.ink2)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.text(11, weight: .semibold))
            .foregroundStyle(AppTheme.ink2)
            .tracking(1.0)
            .padding(.top, 16)
    }

    // MARK: Mutations

    private func handleMove(from source: IndexSet, to destination: Int) {
        // Offsets are relative to the filtered "next up" slice. Translate to absolute.
        let startAbs = queue.currentIndex + 1
        let absSource = IndexSet(source.map { $0 + startAbs })
        let absDestination = destination + startAbs
        queue.move(from: absSource, to: absDestination)
    }

    private func handleDelete(at offsets: IndexSet) {
        let startAbs = queue.currentIndex + 1
        let absOffsets = IndexSet(offsets.map { $0 + startAbs })
        queue.remove(atOffsets: absOffsets)
    }
}
