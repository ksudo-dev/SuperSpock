import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        HSplitView {
            VStack(spacing: 0) {
                RemoteToolbar()
                RemoteCanvas()
                StatusBar()
            }
            .frame(minWidth: 640)
            if model.showInspector { InspectorView().frame(minWidth: 260, idealWidth: 300, maxWidth: 390) }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.showSettings) {
            SettingsView(isOnboarding: !model.hasSavedPassword)
                .environment(model)
                .frame(minWidth: 620, minHeight: 520)
        }
        .focusedSceneValue(\.sessionActions, .init(connect: model.connect, disconnect: model.disconnect, sendCAD: model.sendControlAltDelete))
    }
}

struct RemoteToolbar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        HStack(spacing: 10) {
            Button { [ConnectionState.connected, .authenticated].contains(model.state) ? model.disconnect() : model.connect() } label: {
                Label([ConnectionState.connected, .authenticated].contains(model.state) ? "Disconnect" : "Connect", systemImage: [ConnectionState.connected, .authenticated].contains(model.state) ? "stop.fill" : "play.fill")
            }.buttonStyle(.borderedProminent).tint([ConnectionState.connected, .authenticated].contains(model.state) ? .red : .blue)
            Divider().frame(height: 20)
            Picker("Scale", selection: $model.scaleMode) { ForEach(ScaleMode.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 135)
            Picker("Quality", selection: $model.quality) { ForEach(QualityProfile.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 120)
            Spacer()
            Button { model.showSettings = true } label: { Image(systemName: "gearshape.fill") }.help("Connection Settings")
            Button { model.showLocalCursor.toggle() } label: { Image(systemName: model.showLocalCursor ? "cursorarrow.rays" : "cursorarrow") }.help("Show local cursor")
            Button { model.microphoneMuted.toggle() } label: { Image(systemName: model.microphoneMuted ? "mic.slash.fill" : "mic.fill") }.help("Mute microphone")
            Button { model.audioEnabled.toggle() } label: { Image(systemName: model.audioEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill") }.help("Remote audio")
            Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Full Screen")
            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Inspector")
        }.padding(10).background(.bar)
    }
}

struct RemoteCanvas: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        ZStack {
            Color.black
            if let videoView = model.webRTC.videoView {
                NativeVideoView(videoView: videoView, scaleMode: model.scaleMode)
            } else if let frame = model.frame { Image(decorative: frame, scale: 1).resizable().aspectRatio(contentMode: model.scaleMode == .fill ? .fill : .fit) }
            else { EmptySessionView() }
            if model.showStats && model.state == .connected { StatsOverlay().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding() }
        }.clipped()
    }
}

struct EmptySessionView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "display.and.arrow.down").font(.system(size: 54, weight: .thin)).foregroundStyle(.blue)
            Text(model.device.name).font(.title.bold()).foregroundStyle(.white)
            Text(model.device.endpoint).foregroundStyle(.secondary).textSelection(.enabled)
            switch model.state {
            case .connecting, .authenticating, .reconnecting: ProgressView().controlSize(.large)
            case .failed(let message):
                VStack(spacing: 12) {
                    Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    if !model.hasSavedPassword {
                        Button("Set Up Connection…") { model.showSettings = true }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Connection Settings…") { model.showSettings = true }.buttonStyle(.bordered)
                    }
                }
            case .authenticated:
                VStack(spacing: 9) {
                    Label("Authenticated", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
                    Text("Negotiating native WebRTC video…").foregroundStyle(.secondary)
                    ProgressView()
                }
            default: Button("Connect") { model.connect() }.buttonStyle(.borderedProminent).controlSize(.large)
            }
            Text("Native GLKVM • Tailscale • Hardware H.264").font(.caption).foregroundStyle(.tertiary)
        }.padding(40)
    }
}

struct StatusBar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        HStack {
            Circle().fill(model.state == .connected ? .green : model.state == .authenticated ? .orange : .secondary).frame(width: 7, height: 7)
            Text(model.statusMessage).lineLimit(1)
            Spacer()
            if model.state == .connected, model.metrics.resolution != "—" {
                Text("\(model.metrics.resolution)  •  \(String(format: "%.2f", model.metrics.bitrateMbps)) Mbps  •  WebRTC P2P")
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).frame(height: 26).background(.bar)
    }
}

struct StatsOverlay: View {
    @Environment(AppModel.self) private var model
    var body: some View { VStack(alignment: .leading) { Text(model.metrics.codec).bold(); Text(model.metrics.resolution); Text("\(model.metrics.framesPerSecond) fps"); Text(String(format: "%.1f Mbps", model.metrics.bitrateMbps)); Text("\(model.metrics.latencyMs) ms") }.font(.caption.monospaced()).foregroundStyle(.white).padding(10).background(.black.opacity(0.72), in: .rect(cornerRadius: 8)) }
}
