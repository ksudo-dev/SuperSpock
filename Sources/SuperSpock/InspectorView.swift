import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Inspector", selection: $model.selectedInspectorTab) { ForEach(InspectorTab.allCases) { Image(systemName: icon($0)).tag($0).help($0.rawValue) } }.pickerStyle(.segmented).padding()
            Divider()
            ScrollView { Group { switch model.selectedInspectorTab { case .session: SessionPanel(); case .audio: AudioPanel(); case .display: DisplayPanel(); case .input: InputPanel(); case .diagnostics: DiagnosticsPanel() } }.padding() }
        }.background(Color(nsColor: .controlBackgroundColor))
    }
    func icon(_ tab: InspectorTab) -> String { switch tab { case .session: "network"; case .audio: "waveform"; case .display: "display"; case .input: "keyboard"; case .diagnostics: "gauge.with.dots.needle.50percent" } }
}

struct SessionPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Connection") {
                LabeledContent("Device", value: model.device.name)
                LabeledContent("Address", value: model.device.endpoint)
                Toggle("Reconnect automatically", isOn: $model.reconnectAutomatically)
            }
            Section("Actions") {
                Button("Send Control–Alt–Delete") { model.sendControlAltDelete() }
                Button("Reconnect Now") { model.disconnect(); model.connect() }
            }
        }.formStyle(.grouped)
    }
}
struct AudioPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Remote Audio") { Toggle("Play remote audio", isOn: $model.audioEnabled); Slider(value: $model.volume, in: 0...1) }
            Section("Microphone") { Toggle("Enable microphone", isOn: $model.microphoneEnabled); Toggle("Mute", isOn: $model.microphoneMuted); Toggle("Push to talk", isOn: .constant(false)) }
        }.formStyle(.grouped)
    }
}
struct DisplayPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Presentation") {
                Picker("Scaling", selection: $model.scaleMode) { ForEach(ScaleMode.allCases) { Text($0.rawValue).tag($0) } }
                Picker("Quality", selection: $model.quality) { ForEach(QualityProfile.allCases) { Text($0.rawValue).tag($0) } }
                Toggle("Show local cursor", isOn: $model.showLocalCursor)
                Toggle("Performance overlay", isOn: $model.showStats)
            }
            Section("Stream") { LabeledContent("Codec", value: model.metrics.codec); LabeledContent("Resolution", value: model.metrics.resolution) }
        }.formStyle(.grouped)
    }
}
struct InputPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        Form {
            Section("Capture") { Toggle("Capture keyboard", isOn: $model.captureKeyboard); Toggle("Capture pointer", isOn: $model.capturePointer); Toggle("Synchronize clipboard", isOn: $model.clipboardSync) }
            Section("Keyboard") { Toggle("Swap Command and Control", isOn: .constant(false)); Toggle("Send system shortcuts remotely", isOn: .constant(true)) }
        }.formStyle(.grouped)
    }
}
struct DiagnosticsPanel: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            Section("Live Statistics") { LabeledContent("Resolution", value: model.metrics.resolution); LabeledContent("Bitrate", value: model.metrics.bitrateMbps == 0 ? "Waiting for stream" : String(format: "%.2f Mbps", model.metrics.bitrateMbps)); LabeledContent("Route", value: "P2P"); LabeledContent("Video transport", value: "WebRTC / Janus") }
            Section { Button("Copy Diagnostic Summary") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.diagnosticSummary, forType: .string) } }
        }.formStyle(.grouped)
    }
}
