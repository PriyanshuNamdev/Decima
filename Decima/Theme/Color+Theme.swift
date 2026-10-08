import SwiftUI

extension Color {
    static let nearBlack = Color(hex: "080401")
    static let deepBrownBlack = Color(hex: "100703")
    static let darkBrown = Color(hex: "1A0D07")
    static let warmCharcoal = Color(hex: "252323")
    
    static let coralRed = Color(hex: "F24E4E")
    static let burntOrange = Color(hex: "DC7623")
    static let brightOrange = Color(hex: "FF7A3D")
    static let deepRed = Color(hex: "8F2418")
    
    static let softWhite = Color(hex: "F7F7FB")
    static let lightGray = Color(hex: "A8AAAE")
    static let mutedDarkGray = Color(hex: "6F7074")
    static let charcoalBorder = Color(hex: "313132")
    
    // Gradients
    static let primaryGradient = LinearGradient(
        colors: [coralRed, burntOrange],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    // Hex helper
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
