import SwiftUI

struct SleekTabBar: View {
    @Binding var selected: RootTab

    private let tabs: [(tab: RootTab, icon: String, label: String)] = [
        (.home,    "house",              "Home"),
        (.search,  "magnifyingglass",    "Search"),
        (.library, "books.vertical",     "Library"),
        (.queue,   "list.bullet",        "Queue"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.tab) { item in
                let isActive = selected == item.tab
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        selected = item.tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: isActive ? .semibold : .regular))
                        Text(item.label)
                            .font(.system(size: 10, weight: isActive ? .medium : .regular))
                    }
                    .foregroundStyle(isActive ? Color.mmForeground : Color.mmMutedFg.opacity(0.7))
                    .scaleEffect(isActive ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.2), value: isActive)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .background(
            ZStack {
                Color.mmSurface.opacity(0.85)
                Rectangle().fill(.ultraThinMaterial)
            }
            .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.mmBorder)
                .frame(height: 0.5)
        }
    }
}
