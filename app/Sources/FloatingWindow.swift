import AppKit
import SwiftUI

@MainActor
final class FloatingWindowController {
    static let shared = FloatingWindowController()

    private var window: NSPanel?
    private var alwaysOnTop = true
    private let prefKey = "chronicle.floatingWindowFrame"

    private init() {}

    var isOpen: Bool { window?.isVisible == true }

    func toggle(appState: AppState) {
        if isOpen {
            close()
        } else {
            open(appState: appState)
        }
    }

    func open(appState: AppState) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let style: NSWindow.StyleMask = [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView]
        let panel = NSPanel(
            contentRect: defaultFrame(),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.title = "Chronicle"
        panel.isReleasedWhenClosed = false

        let content = FloatingWindowContent(
            alwaysOnTop: Binding(
                get: { [weak self] in self?.alwaysOnTop ?? true },
                set: { [weak self] newValue in
                    self?.alwaysOnTop = newValue
                    self?.window?.level = newValue ? .floating : .normal
                }
            ),
            onClose: { [weak self] in self?.close() }
        ).environmentObject(appState)

        panel.contentView = NSHostingView(rootView: content)
        panel.makeKeyAndOrderFront(nil)
        self.window = panel
    }

    func close() {
        if let w = window {
            UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: prefKey)
        }
        window?.orderOut(nil)
        window = nil
    }

    private func defaultFrame() -> NSRect {
        if let saved = UserDefaults.standard.string(forKey: prefKey) {
            let rect = NSRectFromString(saved)
            if rect.width > 100 && rect.height > 100 { return rect }
        }
        let width: CGFloat = 360
        let height: CGFloat = 520
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.maxX - width - 20
        let y = screen.maxY - height - 20
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private struct FloatingWindowContent: View {
    @EnvironmentObject var appState: AppState
    @Binding var alwaysOnTop: Bool
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.memories.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.memories) { memory in
                            MemoryCard(memory: memory)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "memorychip.fill")
                .symbolRenderingMode(.hierarchical)
            Text("Chronicle")
                .font(.subheadline.weight(.semibold))
            if appState.isRecording {
                Circle().fill(Color.green).frame(width: 6, height: 6)
            }
            Spacer()
            Toggle(isOn: $alwaysOnTop) {
                Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .focusEffectDisabled()
            .help(alwaysOnTop ? "Pinned — always on top" : "Floating — on top")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .focusEffectDisabled()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No memories yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
