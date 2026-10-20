import SwiftUI
import UIKit

// MARK: - 색

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// 밝은 모드·어두운 모드 색을 함께 정의한다.
    init(light: UInt32, dark: UInt32) {
        self.init(
            uiColor: UIColor { traits in
                UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
            })
    }

    static let cream = Color(light: 0xFBF7F2, dark: 0x1E1A1B)
    static let card = Color(light: 0xFFFFFF, dark: 0x2A2425)
    static let ink = Color(light: 0x3B3335, dark: 0xF3ECEA)
    static let inkSoft = Color(light: 0x8C8183, dark: 0xB3A9AB)
    static let line = Color(light: 0xEFE6E0, dark: 0x3A3234)

    static let rose = Color(light: 0xE58F9E, dark: 0xE297A6)
    static let roseDeep = Color(light: 0xD4707F, dark: 0xEBA3B0)
    static let roseSoft = Color(light: 0xFBE3E7, dark: 0x4A2F36)
    static let sage = Color(light: 0x8FB386, dark: 0x9DBF94)
    static let sageSoft = Color(light: 0xE6F0E2, dark: 0x2E3A2C)
    static let lavender = Color(light: 0xA597D6, dark: 0xB4A8DF)
    static let lavenderSoft = Color(light: 0xECE8F8, dark: 0x332E48)
    static let butter = Color(light: 0xE8BE4F, dark: 0xE3C56F)
    static let butterSoft = Color(light: 0xFCF2D6, dark: 0x403723)
    static let peach = Color(light: 0xEE9E7C, dark: 0xF0AA8C)
    static let peachSoft = Color(light: 0xFCE7DD, dark: 0x45302A)
}

extension CleanupCategory {
    var tint: Color {
        switch self {
        case .blurry: return .lavender
        case .similar: return .rose
        case .screenshot: return .sage
        case .document: return .butter
        case .largeVideo: return .peach
        }
    }

    var softTint: Color {
        switch self {
        case .blurry: return .lavenderSoft
        case .similar: return .roseSoft
        case .screenshot: return .sageSoft
        case .document: return .butterSoft
        case .largeVideo: return .peachSoft
        }
    }
}

// MARK: - 글꼴

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

// MARK: - 카드

struct CardBackground: ViewModifier {
    var padding: CGFloat = 18
    var radius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.rose.opacity(0.10), radius: 14, x: 0, y: 6)
    }
}

extension View {
    func card(padding: CGFloat = 18, radius: CGFloat = 22) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }
}

// MARK: - 버튼

/// 눌렀을 때 살짝 작아지는 스프링 효과.
struct SoftPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 둥근 알약 모양 버튼.
struct PillButtonStyle: ButtonStyle {
    var filled = false
    var tint: Color = .rose

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(.subheadline, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(filled ? Color.white : tint)
            .background(
                Capsule().fill(filled ? tint : tint.opacity(0.14))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - 형식

enum Format {
    static func bytes(_ value: Int64) -> String {
        if value <= 0 { return "0MB" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, value))
    }

    static func count(_ value: Int) -> String {
        value.formatted()
    }

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 (E) a h:mm"
        return formatter
    }()

    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
