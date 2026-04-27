import SwiftUI

enum RootTab: Hashable {
    case home
    case search
    case library
    case queue
}

final class TabRouter: ObservableObject {
    @Published var selected: RootTab = .home
}
