import SwiftUI
import UIKit

/// The city-guide palette shared with the approved landing page.
enum GuideTheme {
    static let paper = adaptive(0xF6F1E8, dark: 0x142630)
    static let surface = adaptive(0xFFFEFA, dark: 0x20343E)
    static let ink = adaptive(0x192B35, dark: 0xF6F1E8)
    static let muted = adaptive(0x626E73, dark: 0xB7C9C9)
    static let line = adaptive(0xD8D6CD, dark: 0x49606A)
    static let teal = adaptive(0x147D79, dark: 0xA7D6C9)
    static let tealInk = adaptive(0x116F6B, dark: 0xA7D6C9)
    static let tealPale = adaptive(0xD9EEEA, dark: 0x294A48)
    static let amber = adaptive(0xAE651E, dark: 0xEDC86B)
    static let amberInk = adaptive(0x965C1E, dark: 0xEDC86B)
    static let amberPale = adaptive(0xF7E8CF, dark: 0x493B27)
    static let warning = adaptive(0xAA483D, dark: 0xFFADA0)
    static let warningPale = adaptive(0xF7E2DC, dark: 0x4A302E)

    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("AvenirNext-Bold", size: size, relativeTo: style)
    }
    static func editorial(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Georgia", size: size, relativeTo: style)
    }
    static func body(_ size: CGFloat = 16, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom("AvenirNext-Regular", size: size, relativeTo: style)
    }
    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct GuideWordmark: View {
    var size: CGFloat = 30
    var showPin = true
    var body: some View {
        HStack(spacing: 8) {
            if showPin {
                GuidePinShape().fill(GuideTheme.teal, style: FillStyle(eoFill: true))
                    .frame(width: size * 0.8, height: size)
                    .accessibilityHidden(true)
            }
            (Text("iYosi").foregroundColor(GuideTheme.ink) + Text(".").foregroundColor(GuideTheme.teal))
                .font(GuideTheme.heading(size)).tracking(-1.4)
        }.accessibilityElement(children: .ignore).accessibilityLabel("iYosi")
    }
}

struct GuideEyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(GuideTheme.heading(11, relativeTo: .caption))
            .tracking(1.6).foregroundStyle(GuideTheme.tealInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Native path matching the landing page favicon, including its open center.
private struct GuidePinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 64
        let sy = rect.height / 64
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: point(32, 8))
        path.addCurve(to: point(9, 31), control1: point(19, 8), control2: point(9, 18))
        path.addCurve(to: point(32, 59), control1: point(9, 49), control2: point(32, 59))
        path.addCurve(to: point(55, 31), control1: point(32, 59), control2: point(55, 49))
        path.addCurve(to: point(32, 8), control1: point(55, 18), control2: point(45, 8))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.minX + 23 * sx, y: rect.minY + 21 * sy, width: 18 * sx, height: 18 * sy))
        return path
    }
}

extension AdvisoryStatus {
    var guideTitle: String {
        switch self {
        case .verifiedDesignated: "Evidence-reviewed designation"
        case .communityReported: "Community report · unverified"
        case .disputed: "Disputed"
        case .prohibited: "Prohibited · warning"
        case .closed: "Closed"
        }
    }
    var guideSymbol: String {
        switch self {
        case .verifiedDesignated: "checkmark"
        case .communityReported: "diamond"
        case .disputed: "exclamationmark.triangle.fill"
        case .prohibited: "nosign"
        case .closed: "xmark"
        }
    }
    var guideColor: Color {
        switch self {
        case .verifiedDesignated: GuideTheme.teal
        case .communityReported: GuideTheme.amber
        case .disputed, .prohibited, .closed: GuideTheme.warning
        }
    }
    var guideBackground: Color {
        switch self {
        case .verifiedDesignated: GuideTheme.tealPale
        case .communityReported: GuideTheme.amberPale
        case .disputed, .prohibited, .closed: GuideTheme.warningPale
        }
    }
    var guideTextColor: Color {
        switch self {
        case .verifiedDesignated: GuideTheme.tealInk
        case .communityReported: GuideTheme.amberInk
        case .disputed, .prohibited, .closed: GuideTheme.warning
        }
    }
}

struct GuideStatusBadge: View {
    let status: AdvisoryStatus
    var body: some View {
        Label(status.guideTitle, systemImage: status.guideSymbol)
            .font(GuideTheme.heading(13, relativeTo: .subheadline))
            .foregroundStyle(status.guideTextColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(status.guideBackground, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct GuideFact: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundStyle(GuideTheme.teal).frame(width: 34, height: 34)
                .background(GuideTheme.tealPale, in: RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased()).font(GuideTheme.heading(10, relativeTo: .caption2))
                    .tracking(1.2).foregroundStyle(GuideTheme.muted)
                Text(value).font(GuideTheme.body(15, relativeTo: .subheadline)).foregroundStyle(GuideTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct GuideNotice: View {
    let text: String
    var symbol = "info.circle"
    var warning = false
    var body: some View {
        Label {
            Text(text).font(GuideTheme.body(14, relativeTo: .subheadline))
                .fixedSize(horizontal: false, vertical: true)
        } icon: { Image(systemName: symbol) }
        .foregroundStyle(warning ? GuideTheme.warning : GuideTheme.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(warning ? GuideTheme.warningPale : GuideTheme.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct GuideButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(GuideTheme.heading(15, relativeTo: .body))
            .frame(minHeight: 24).padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(secondary ? GuideTheme.ink : GuideTheme.paper)
            .background(secondary ? GuideTheme.surface : GuideTheme.ink, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(GuideTheme.line, lineWidth: secondary ? 1 : 0) }
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func guideScreen() -> some View {
        self.font(GuideTheme.body()).foregroundStyle(GuideTheme.ink)
            .tint(GuideTheme.tealInk).background(GuideTheme.paper)
            .toolbarBackground(GuideTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
    func guideForm() -> some View {
        self.scrollContentBackground(.hidden).guideScreen()
    }
    func guideCard() -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(GuideTheme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(GuideTheme.line, lineWidth: 1) }
    }
}
