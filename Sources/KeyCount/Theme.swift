import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(NSColor(name: "KeyCountAccent") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.36, green: 0.80, blue: 0.69, alpha: 1)
            : NSColor(srgbRed: 0.08, green: 0.43, blue: 0.36, alpha: 1)
    })
    static let background = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let border = Color.primary.opacity(0.07)
    static let muted = Color.primary.opacity(0.055)
    static let warning = Color.orange

    static let appIcon: NSImage = {
        // Preview renderer supplies its own resource folder; the app uses its bundle.
        let previewURL = ProcessInfo.processInfo.environment["KEYCOUNT_PREVIEW_RESOURCES"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("AppIcon.png") }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") ?? previewURL,
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "keyboard", accessibilityDescription: "KeyCount")!
    }()
}

struct PanelCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.border, lineWidth: 1)
            }
    }
}

struct QuietIconButton: View {
    let symbol: String
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: 8))
        .help(title)
        .accessibilityLabel(title)
    }
}
