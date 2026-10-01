import SwiftUI

enum AppTheme {
    static let purple = Color(red: 107/255, green: 44/255, blue: 145/255)
    static let deep = Color(red: 53/255, green: 19/255, blue: 74/255)
    static let ink = Color(red: 32/255, green: 26/255, blue: 34/255)
    static let muted = Color(red: 103/255, green: 95/255, blue: 105/255)
    static let line = Color(red: 231/255, green: 221/255, blue: 233/255)

    static func background(for level: AttendanceLevel) -> Color {
        switch level {
        case .green: return Color(red: 220/255, green: 245/255, blue: 231/255)
        case .amber: return Color(red: 1, green: 241/255, blue: 199/255)
        case .red: return Color(red: 1, green: 226/255, blue: 226/255)
        }
    }

    static func foreground(for level: AttendanceLevel) -> Color {
        switch level {
        case .green: return Color(red: 20/255, green: 94/255, blue: 59/255)
        case .amber: return Color(red: 104/255, green: 70/255, blue: 0)
        case .red: return Color(red: 132/255, green: 25/255, blue: 25/255)
        }
    }
}

struct CompactButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .foregroundStyle(primary ? .white : AppTheme.purple)
            .padding(.horizontal, 11)
            .frame(minHeight: 38)
            .background(primary ? AppTheme.purple : Color.white)
            .overlay(Rectangle().stroke(primary ? AppTheme.purple : AppTheme.line))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

