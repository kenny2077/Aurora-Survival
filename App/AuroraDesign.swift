import SwiftUI

enum AuroraDesign {
    static let readableWidth: CGFloat = 752

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let compact: CGFloat = 12
        static let standard: CGFloat = 16
        static let prominent: CGFloat = 22
    }

    static let spruce = Color(
        red: 28 / 255,
        green: 73 / 255,
        blue: 57 / 255
    )
    static let signal = Color(
        red: 166 / 255,
        green: 48 / 255,
        blue: 15 / 255
    )
    static let river = Color(
        red: 0 / 255,
        green: 111 / 255,
        blue: 116 / 255
    )
    static let aurora = LinearGradient(
        colors: [river, Color.indigo.opacity(0.82)],
        startPoint: .leading,
        endPoint: .trailing
    )
}
