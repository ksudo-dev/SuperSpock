import SwiftUI

@main
struct SuperSpockApp: App {
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
