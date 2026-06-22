import AppKit
import SwiftUI

struct GlassIconButtonStyle: ButtonStyle {
    var size: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.44 : 0.26))
            )
            .overlay(
                Circle()
                    .strokeBorder(Color(nsColor: .white).opacity(0.20), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct GlassPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color(nsColor: .white).opacity(0.25), lineWidth: 1)
            )
    }
}

struct GlassSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(configuration.isPressed ? 0.38 : 0.22))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color(nsColor: .white).opacity(0.18), lineWidth: 1)
            )
    }
}

struct GlassDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 1)
    }
}
