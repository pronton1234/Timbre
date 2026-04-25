import SwiftUI

/// A fallback gradient tile rendered in place of real artwork.
///
/// Ported from the Claude Design `ART_PALETTES` / `ART_MOTIFS` in `shared.jsx`.
/// A stable integer seed deterministically picks one of 10 palettes and one of
/// 4 motifs so the same track always renders the same tile across launches.
struct ArtTile: View {
    let seed: Int
    let size: CGFloat
    var cornerRadius: CGFloat = 12

    init(seed: Int, size: CGFloat, cornerRadius: CGFloat? = nil) {
        self.seed = seed
        self.size = size
        if let r = cornerRadius {
            self.cornerRadius = r
        } else {
            self.cornerRadius = ArtTile.defaultCornerRadius(for: size)
        }
    }

    static func defaultCornerRadius(for size: CGFloat) -> CGFloat {
        if size >= 200 { return 14 }
        if size >= 120 { return 12 }
        if size >= 60  { return 8 }
        return 6
    }

    /// Convenience: seed from any hashable id (e.g. a track id string).
    static func seed<T: Hashable>(from value: T) -> Int {
        abs(stableHash(value))
    }

    private static func stableHash<T: Hashable>(_ value: T) -> Int {
        // `String.hashValue` is randomized per launch; fall back to a FNV-1a
        // over the description so the palette is stable.
        let s = String(describing: value)
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            h ^= UInt64(byte)
            h &*= 0x100000001b3
        }
        return Int(truncatingIfNeeded: h)
    }

    var body: some View {
        let palette = ArtPalette.all[seed % ArtPalette.all.count]
        let motif   = ArtMotif.all[(seed / ArtPalette.all.count) % ArtMotif.all.count]

        ZStack {
            LinearGradient(
                colors: [palette.from, palette.to],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            motif.shape
                .fill(Color.white.opacity(0.20))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Palettes

struct ArtPalette {
    let from: Color
    let to: Color

    /// The ten gradients from `shared.jsx` → `ART_PALETTES` (V2 cozy look).
    static let all: [ArtPalette] = [
        .init(from: rgb(139,152, 97), to: rgb(164,124, 92)),   // sage → clay
        .init(from: rgb(180,128,107), to: rgb(120, 86, 74)),   // terracotta → cocoa
        .init(from: rgb(199,164,123), to: rgb(134,105, 79)),   // honey → walnut
        .init(from: rgb(156,134,168), to: rgb(108, 97,138)),   // mauve → plum
        .init(from: rgb(150,178,165), to: rgb(104,130,128)),   // sage-mint → pine
        .init(from: rgb(210,174,125), to: rgb(164,126, 81)),   // amber → caramel
        .init(from: rgb(108,120,134), to: rgb( 82, 93,110)),   // dusk → slate
        .init(from: rgb(173,156,142), to: rgb(121,106, 96)),   // sand → taupe
        .init(from: rgb(134,162,130), to: rgb( 95,121, 92)),   // moss → forest
        .init(from: rgb(196,130,129), to: rgb(140, 86, 90)),   // rose → oxblood
    ]

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255)
    }
}

// MARK: - Motifs

struct ArtMotif {
    let shape: AnyShape

    static let all: [ArtMotif] = [
        .init(shape: AnyShape(CircleMotif())),
        .init(shape: AnyShape(DiagonalMotif())),
        .init(shape: AnyShape(ArcMotif())),
        .init(shape: AnyShape(GridMotif())),
    ]
}

private struct CircleMotif: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.35
        let c = CGPoint(x: rect.midX + rect.width * 0.15, y: rect.midY - rect.height * 0.10)
        return Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}

private struct DiagonalMotif: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let band = rect.height * 0.22
        p.move(to: CGPoint(x: rect.minX, y: rect.midY + band / 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + band / 2))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY - band / 2))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY - band / 2))
        p.closeSubpath()
        return p
    }
}

private struct ArcMotif: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) * 0.6
        let c = CGPoint(x: rect.minX + rect.width * 0.30, y: rect.maxY + rect.height * 0.05)
        p.addArc(center: c, radius: r,
                 startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        p.addLine(to: CGPoint(x: c.x + r * cos(.pi * 200/180), y: c.y + r * sin(.pi * 200/180)))
        p.closeSubpath()
        return p
    }
}

private struct GridMotif: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let step = rect.width * 0.22
        var y = rect.minY + step * 0.5
        while y < rect.maxY {
            p.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: 1.5))
            y += step
        }
        return p
    }
}
