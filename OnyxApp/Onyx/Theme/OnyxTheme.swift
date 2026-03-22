import SwiftUI

enum OnyxTheme {
    // MARK: - Colors
    enum Colors {
        static let background = Color.white.opacity(0.05)
        static let surface = Color.white.opacity(0.06)
        static let surfaceHover = Color.white.opacity(0.09)
        static let surfaceSelected = Color.white.opacity(0.12)
        static let border = Color.white.opacity(0.12)

        static let textPrimary = Color.white.opacity(0.9)
        static let textSecondary = Color.white.opacity(0.6)
        static let textTertiary = Color.white.opacity(0.4)

        static let accent = Color(red: 0.400, green: 0.520, blue: 1.0)
        static let accentSubtle = Color(red: 0.400, green: 0.520, blue: 1.0).opacity(0.15)

        static let destructive = Color(red: 0.900, green: 0.300, blue: 0.300)

        static let cursorColors: [Color] = [
            Color(red: 0.400, green: 0.800, blue: 0.600),
            Color(red: 0.900, green: 0.600, blue: 0.300),
            Color(red: 0.800, green: 0.400, blue: 0.800),
            Color(red: 0.300, green: 0.700, blue: 0.900),
            Color(red: 0.900, green: 0.400, blue: 0.500),
        ]
    }

    // MARK: - Typography
    enum Typography {
        static let heading1 = Font.system(size: 28, weight: .bold, design: .default)
        static let heading2 = Font.system(size: 22, weight: .semibold, design: .default)
        static let heading3 = Font.system(size: 18, weight: .semibold, design: .default)
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        static let bodyMono = Font.system(size: 12, weight: .regular, design: .monospaced)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let label = Font.system(size: 13, weight: .medium, design: .default)
        static let sidebarItem = Font.system(size: 13, weight: .light, design: .default)
        static let sidebarSection = Font.system(size: 11, weight: .semibold, design: .default)

        static func nsFont(for blockType: String, size: CGFloat = 15) -> NSFont {
            switch blockType {
            case "heading1":
                return NSFont.systemFont(ofSize: 28, weight: .bold)
            case "heading2":
                return NSFont.systemFont(ofSize: 22, weight: .semibold)
            case "heading3":
                return NSFont.systemFont(ofSize: 18, weight: .semibold)
            case "code":
                return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            default:
                return NSFont.systemFont(ofSize: size, weight: .regular)
            }
        }
    }

    // MARK: - Spacing (4pt grid)
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    // MARK: - Radius
    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
    }

    // MARK: - Animation
    enum Animation {
        static let quick = SwiftUI.Animation.spring(duration: 0.15, bounce: 0.2)
        static let standard = SwiftUI.Animation.spring(duration: 0.25, bounce: 0.15)
        static let slow = SwiftUI.Animation.spring(duration: 0.4, bounce: 0.1)
        static let cursor = SwiftUI.Animation.spring(duration: 0.1, bounce: 0.0)
    }
}

// MARK: - View Modifiers

struct OnyxSurface: ViewModifier {
    var isHovered: Bool = false
    var isSelected: Bool = false

    func body(content: Content) -> some View {
        content
            .background(
                isSelected ? OnyxTheme.Colors.surfaceSelected :
                isHovered ? OnyxTheme.Colors.surfaceHover :
                OnyxTheme.Colors.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: OnyxTheme.Radius.md))
    }
}

extension View {
    func onyxSurface(isHovered: Bool = false, isSelected: Bool = false) -> some View {
        modifier(OnyxSurface(isHovered: isHovered, isSelected: isSelected))
    }
}

// MARK: - Small Icon Button (14×14)

struct SmallIconButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(
                    isActive ? OnyxTheme.Colors.textPrimary :
                    isHovered ? OnyxTheme.Colors.textSecondary :
                    OnyxTheme.Colors.textTertiary
                )
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: OnyxTheme.Radius.sm)
                        .fill(isActive ? OnyxTheme.Colors.surface.opacity(0.6) :
                              isHovered ? OnyxTheme.Colors.surface.opacity(0.4) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(OnyxTheme.Animation.quick) {
                isHovered = hovering
            }
        }
    }
}
