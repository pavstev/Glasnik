import SwiftUI

/// Šapat's visual identity — warm **copper-on-stone**, mirroring the app icon
/// (`scripts/make-icon.swift`). One token set for the whole UI so views stop mixing
/// the system-blue accent with ad-hoc 1/4/5/8/10/12/14/16pt spacing.
///
/// The popover is pinned to a dark appearance (see `AppDelegate`), so these colors are
/// authored for a dark stone surface.
enum Theme {
    // MARK: Palette

    /// Popover background — deep stone. `#23201C`.
    static let stone = Color(red: 0.137, green: 0.125, blue: 0.110)
    /// Raised card surface. `#2C2823`.
    static let stoneRaised = Color(red: 0.173, green: 0.157, blue: 0.137)
    /// Recessed surface (footer). `#1F1C18`.
    static let stoneSunken = Color(red: 0.122, green: 0.110, blue: 0.094)

    /// Primary accent — deep copper. `#C97E47`.
    static let copper = Color(red: 0.788, green: 0.494, blue: 0.278)
    /// Lighter copper for highlights / hover. `#E2A56F`.
    static let copperLight = Color(red: 0.886, green: 0.647, blue: 0.435)

    /// Warm off-white — primary text. `#F2EBE2`.
    static let textPrimary = Color(red: 0.949, green: 0.922, blue: 0.886)
    /// Muted warm gray — secondary text. `#B8AE9F`.
    static let textSecondary = Color(red: 0.722, green: 0.682, blue: 0.624)
    /// Faint warm gray — hints / labels. `#8A8073`.
    static let textTertiary = Color(red: 0.541, green: 0.502, blue: 0.451)

    /// Copper-tinted hairline for dividers and borders on stone.
    static let hairline = copperLight.opacity(0.16)
    /// Soft copper wash for accent fills (banners, active pills).
    static let copperWash = copper.opacity(0.14)

    /// Recording indicator (kept system-red for instant recognizability).
    static let recording = Color(red: 0.906, green: 0.298, blue: 0.235)
    /// Positive/up-to-date affordance — a muted sage that reads on stone.
    static let positive = Color(red: 0.624, green: 0.722, blue: 0.604)

    // MARK: Spacing scale (4-pt grid)

    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20

    // MARK: Corner radii

    static let rSmall: CGFloat = 8
    static let rCard: CGFloat = 12
    static let rPanel: CGFloat = 16

    // MARK: Layout

    /// Fixed popover width. The content sizes the height.
    static let popoverWidth: CGFloat = 400
}

extension View {
    /// A standard raised card: stone-raised fill, hairline border, card radius.
    func cardSurface(_ radius: CGFloat = Theme.rCard) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.stoneRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 0.5)
        )
    }
}
