import SwiftUI
import UIKit

// MARK: - MinimalMusic color tokens

extension Color {
    static let mmBackground     = Color(white: 0.07)   // #0B0B0B
    static let mmForeground     = Color(white: 0.98)   // #FAFAFA
    static let mmSurface        = Color(white: 0.10)   // #191919
    static let mmSurfaceElevated = Color(white: 0.13)  // #212121
    static let mmMuted          = Color(white: 0.14)   // #242424
    static let mmMutedFg        = Color(white: 0.60)   // #999999
    static let mmBorder         = Color(white: 0.18)   // #2E2E2E
    static let mmPlayerBg       = Color(white: 0.12)   // #1F1F1F
    static let mmAccent         = Color(hue: 141.0/360.0, saturation: 0.73, brightness: 0.66) // #1DB954
}

extension Font {
    static func display(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size)
    }
}

var stageGradient: RadialGradient {
    RadialGradient(
        colors: [Color(white: 0.14), Color(white: 0.06)],
        center: .top,
        startRadius: 10,
        endRadius: 700
    )
}

// MARK: - Legacy AppTheme (aliased to mm tokens so existing call-sites compile)

enum AppTheme {
    static let bg               = Color.mmBackground
    static let background       = Color.mmBackground
    static let card             = Color.mmSurface
    static let surface          = Color.mmSurface
    static let surfaceElevated  = Color.mmSurfaceElevated

    static let ink              = Color.mmForeground
    static let text             = Color.mmForeground
    static let ink2             = Color.mmMutedFg
    static let textSecondary    = Color.mmMutedFg
    static let ink3             = Color.mmMutedFg
    static let hair             = Color.mmBorder
    static let divider          = Color.mmBorder
    static let accent           = Color.mmAccent
    static let accentTint       = Color.mmAccent.opacity(0.3)

    static let likedGradient = LinearGradient(
        colors: [Color.mmAccent.opacity(0.8), Color.mmAccent.opacity(0.4)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let playlistGradient = LinearGradient(
        colors: [Color(red: 0.145, green: 0.388, blue: 0.921),
                 Color(red: 0.118, green: 0.251, blue: 0.686)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let fullPlayerBg = LinearGradient(
        colors: [Color.mmSurface, Color.mmBackground],
        startPoint: .top, endPoint: .bottom)

    static let shadowSoft   = Color.black.opacity(0.30)
    static let shadowStrong = Color.black.opacity(0.60)

    static func text(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
    static func display(_ size: CGFloat) -> Font { Font.display(size) }
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        Font.display(size)
    }
    static let display1 = Font.display(30)
    static let display2 = Font.display(20)
    static let display3 = Font.display(24)
    static let display  = Font.display(30)
    static let section  = Font.system(size: 20, weight: .bold)
}

// MARK: - UIKit appearance

enum AppAppearance {
    static func configure() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(Color.mmBackground)
        nav.shadowColor = .clear
        nav.titleTextAttributes      = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance    = nav
        UINavigationBar.appearance().tintColor            = .white

        UITableView.appearance().backgroundColor     = .clear
        UITableViewCell.appearance().backgroundColor = .clear
    }
}

// MARK: - Helpers

extension View {
    func appBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Color.mmBackground.ignoresSafeArea())
    }
}
