import Foundation
import CoreText

/// Belt-and-braces font registration for the bundled cozy-remote typefaces.
///
/// XcodeGen's `UIAppFonts` entry in `project.yml` already tells iOS to load the
/// six TTFs from `Resources/Fonts/`, but this helper re-registers them via
/// `CTFontManagerRegisterFontsForURL` at launch so the fonts still resolve if
/// someone regenerates Info.plist manually and drops the `UIAppFonts` key.
enum FontLoader {
    private static let fileNames = [
        "DMSerifDisplay-Regular",
        "DMSerifDisplay-Italic",
        "Manrope-Regular",
        "Manrope-Medium",
        "Manrope-SemiBold",
        "Manrope-Bold",
    ]

    /// Register every bundled TTF with CoreText. Safe to call multiple times —
    /// `CTFontManagerRegisterFontsForURL` returns a duplicate-registration
    /// error that we swallow silently.
    static func registerBundledFonts() {
        let bundle = Bundle.main
        for name in fileNames {
            guard let url = bundle.url(forResource: name, withExtension: "ttf")
                    ?? bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts") else {
                continue
            }
            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Ignore errors: most likely the font was already registered via
            // the Info.plist `UIAppFonts` mechanism, which is fine.
        }
    }
}
