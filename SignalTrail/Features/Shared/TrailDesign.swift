import SwiftUI

enum TrailTheme {
    static let accent = Color(uiColor: AppTheme.accent)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
}

struct TrailCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TrailTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct TrailSectionHeading: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.title2.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrailPrimaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            button.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        } else {
            button.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .tint(TrailTheme.accent)
    }
}

struct TrailSecondaryButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            button.buttonStyle(.glass).buttonBorderShape(.capsule)
        } else {
            button.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
    }

    private var button: some View {
        Button(action: action) { Label(title, systemImage: symbol).padding(.vertical, 6) }
    }
}

extension View {
    @ViewBuilder
    func trailActionBar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom) {
                GlassEffectContainer(spacing: 16) {
                    content().padding(.horizontal, 20).padding(.vertical, 12)
                }
            }
        } else {
            safeAreaInset(edge: .bottom) {
                content().padding(.horizontal, 20).padding(.vertical, 12)
                    .background(TrailTheme.background)
            }
        }
    }
}
