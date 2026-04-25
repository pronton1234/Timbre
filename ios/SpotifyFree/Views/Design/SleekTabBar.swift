import SwiftUI

/// Bottom tab bar matching the Sleek Music App reference:
/// 4 tappable items (Home, Search, Library, Queue). The first 3 switch the
/// selected `RootTab`; the 4th (Queue) triggers a modal via `onQueueTap`
/// and does NOT select a tab.
struct SleekTabBar: View {
    @Binding var selected: RootTab
    var onQueueTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .home,    icon: "house.fill",             label: "Home")
            tabButton(tab: .search,  icon: "magnifyingglass",        label: "Search")
            tabButton(tab: .library, icon: "books.vertical.fill",    label: "Library")
            queueButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(
            ZStack {
                AppTheme.card.opacity(0.95)
                Rectangle().fill(.ultraThinMaterial).opacity(0.6)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppTheme.hair)
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func tabButton(tab: RootTab, icon: String, label: String) -> some View {
        let isActive = (selected == tab)
        Button {
            selected = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .regular))
                Text(label)
                    .font(AppTheme.text(11, weight: .medium))
            }
            .foregroundStyle(isActive ? AppTheme.ink : AppTheme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var queueButton: some View {
        Button(action: onQueueTap) {
            VStack(spacing: 2) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 22, weight: .regular))
                Text("Queue")
                    .font(AppTheme.text(11, weight: .medium))
            }
            .foregroundStyle(AppTheme.ink2)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
