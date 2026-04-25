import SwiftUI

/// Root-level tabs. Queue is NOT a tab in the sleek design — it opens as a
/// fullScreenCover modal from the tab bar. Shared across the app via
/// `@EnvironmentObject` so any screen can programmatically switch tabs.
enum RootTab: Hashable {
    case home
    case search
    case library
}

final class TabRouter: ObservableObject {
    @Published var selected: RootTab = .home
}
