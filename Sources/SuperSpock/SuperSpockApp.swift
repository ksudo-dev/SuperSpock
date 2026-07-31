import SwiftUI

// When launched as a bare executable (swift run) instead of a .app bundle,
// macOS treats the process as a background agent: no Dock icon, and the
// window never reliably becomes key, so typing goes nowhere. Forcing the
// regular activation policy fixes both.
final class ActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

// Entry point dispatch: `SuperSpock --probe <https-endpoint>` runs the full
// auth + Janus/WebRTC handshake headless and prints every signaling step,
// so the negotiation can be debugged from a terminal without Xcode.
@main
enum Main {
    static func main() {
        if let probeIndex = CommandLine.arguments.firstIndex(of: "--probe") {
            let endpoint = CommandLine.arguments.indices.contains(probeIndex + 1)
                ? CommandLine.arguments[probeIndex + 1]
                : ""
            ProbeRunner.run(endpoint: endpoint, allowInsecureTLS: CommandLine.arguments.contains("--insecure"))
        } else {
            SuperSpockApp.main()
        }
    }
}

struct SuperSpockApp: App {
    @NSApplicationDelegateAdaptor(ActivationDelegate.self) private var activationDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentMinSize)
        .commands { SuperSpockCommands() }

        Settings { SettingsView().environment(model).frame(width: 620, height: 520) }
    }
}

struct SuperSpockCommands: Commands {
    @FocusedValue(\.sessionActions) private var actions
    var body: some Commands {
        CommandMenu("Session") {
            Button("Connect") { actions?.connect() }.keyboardShortcut("k", modifiers: [.command])
            Button("Disconnect") { actions?.disconnect() }.keyboardShortcut("k", modifiers: [.command, .shift])
            Divider()
            Button("Send Control–Alt–Delete") { actions?.sendCAD() }
            Button("Toggle Full Screen") { NSApp.keyWindow?.toggleFullScreen(nil) }.keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}

struct SessionActions {
    let connect: () -> Void
    let disconnect: () -> Void
    let sendCAD: () -> Void
}

private struct SessionActionsKey: FocusedValueKey { typealias Value = SessionActions }
extension FocusedValues { var sessionActions: SessionActions? { get { self[SessionActionsKey.self] } set { self[SessionActionsKey.self] = newValue } } }
