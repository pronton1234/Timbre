import SwiftUI
import UIKit

/// Design tokens for the "Sleek Music App" look — dark Spotify-style palette,
/// pure SF Pro (system) typography. Keep this file presentational only.
enum AppTheme {
    // MARK: Colors

    /// Root background — pure black.
    static let bg               = Color.black
    /// Legacy alias used by older call-sites still being rewritten.
    static let background       = Color.black
    /// Deep card (tab bar, nav chrome) — zinc-900.
    static let card             = Color(red: 0.094, green: 0.094, blue: 0.106) // #18181B
    /// Surface (mini player, queue rows) — zinc-800.
    static let surface          = Color(red: 0.153, green: 0.153, blue: 0.165) // #27272A
    /// Elevated/hover — zinc-700 @ 60%.
    static let surfaceElevated  = Color(red: 0.247, green: 0.247, blue: 0.275).opacity(0.6) // #3F3F46 @ 0.6

    /// Primary text, active icons.
    static let ink              = Color.white
    /// Legacy alias kept so older call-sites compile.
    static let text             = Color.white
    /// Secondary text, inactive icons — gray-400.
    static let ink2             = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF
    static let textSecondary    = Color(red: 0.612, green: 0.639, blue: 0.686)
    /// Tertiary text, placeholder — gray-500.
    static let ink3             = Color(red: 0.420, green: 0.447, blue: 0.502) // #6B7280
    /// Hairline — zinc-800 (same as surface).
    static let hair             = Color(red: 0.153, green: 0.153, blue: 0.165)
    static let divider          = Color(red: 0.153, green: 0.153, blue: 0.165)
    /// Accent (pure white — no Spotify green).
    static let accent           = Color.white
    static let accentTint       = Color(red: 0.247, green: 0.247, blue: 0.275).opacity(0.6)

    // MARK: Gradients (Library category tiles)

    static let likedGradient = LinearGradient(
        colors: [Color(red: 0.494, green: 0.133, blue: 0.808),   // purple-700 #7E22CE
                 Color(red: 0.345, green: 0.109, blue: 0.529)],  // purple-900 #581C87
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let playlistGradient = LinearGradient(
        colors: [Color(red: 0.145, green: 0.388, blue: 0.921),   // blue-600 #2563EB
                 Color(red: 0.118, green: 0.251, blue: 0.686)],  // blue-800 #1E40AF
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let fullPlayerBg = LinearGradient(
        colors: [Color(red: 0.153, green: 0.153, blue: 0.165),   // zinc-800
                 Color.black],
        startPoint: .top, endPoint: .bottom)

    // MARK: Shadows

    static let shadowSoft   = Color.black.opacity(0.30)
    static let shadowStrong = Color.black.opacity(0.60)

    // MARK: Fonts — SF Pro (system). No serif, no custom font.

    /// Primary text helper. `weight` maps directly to SwiftUI's Font.Weight.
    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    /// Back-compat aliases used by old call-sites. All resolve to system sans.
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }
    /// Pre-baked styles.
    static let display1 = Font.system(size: 30, weight: .bold)
    static let display2 = Font.system(size: 20, weight: .bold)
    static let display3 = Font.system(size: 24, weight: .bold)
    static let display  = Font.system(size: 30, weight: .bold)
    static let section  = Font.system(size: 20, weight: .bold)
}

// MARK: - UIKit appearance

/// Dark UIKit appearance so NavigationStack chrome + any residual UITabBar
/// inherits the sleek palette. The custom HStack tab bar handles the real
/// bottom nav; this is only a safety net.
enum AppAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor.black
        nav.shadowColor = .clear

        let largeFont  = UIFont.systemFont(ofSize: 30, weight: .bold)
        let inlineFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let textColor  = UIColor.white

        nav.largeTitleTextAttributes = [.font: largeFont,  .foregroundColor: textColor]
        nav.titleTextAttributes      = [.font: inlineFont, .foregroundColor: textColor]

        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance    = nav
        UINavigationBar.appearance().tintColor            = .white

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(AppTheme.card)
        tab.shadowColor = UIColor(AppTheme.hair)

        let item = tab.stackedLayoutAppearance
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        item.normal.iconColor = UIColor(AppTheme.ink2)
        item.normal.titleTextAttributes   = [.foregroundColor: UIColor(AppTheme.ink2)]

        UITabBar.appearance().standardAppearance    = tab
        UITabBar.appearance().scrollEdgeAppearance  = tab
        UITabBar.appearance().isTranslucent         = false

        let seg = UISegmentedControl.appearance()
        seg.backgroundColor          = UIColor(AppTheme.surface)
        seg.selectedSegmentTintColor = .white
        seg.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        seg.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)

        UITableView.appearance().backgroundColor     = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }
}

// MARK: - Helpers

extension View {
    /// Paints the black app background behind a scrolling view (List/ScrollView).
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg.ignoresSafeArea())
    }
}
