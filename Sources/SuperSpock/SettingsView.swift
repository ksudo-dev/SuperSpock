import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var isOnboarding = false
    @State private var password = ""
    @State private var totpSecret = ""
    @State private var savedMessage = ""
    @State private var securityError = ""
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if isOnboarding {
                VStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 34)).foregroundStyle(.blue)
                    Text("Connect SuperSpock").font(.title2.bold())
                    Text("One-time setup. No Keychain and no recurring OTP entry.").foregroundStyle(.secondary)
                }.padding(.top, 22)
            }
            TabView {
            Form {
                TextField("Display name", text: $model.device.name)
                TextField("GLKVM address", text: $model.device.endpoint)
                Text("Use the exact HTTPS Tailscale hostname. The certificate is validated automatically by macOS.").font(.caption).foregroundStyle(.secondary)
                Button("Save Connection") { model.saveDevice(); savedMessage = "Connection saved" }
            }.padding().tabItem { Label("Connection", systemImage: "network") }
            Form {
                SecureField("Admin password", text: $password)
                    .textContentType(.password)
                SecureField("2FA setup key or otpauth link", text: $totpSecret)
                VStack(alignment: .leading, spacing: 5) {
                    Label("Enter this once — do not enter the rotating six-digit code.", systemImage: "key.fill").font(.callout.bold())
                    Text("SuperSpock stores the setup key in a private FileVault-protected local vault and generates every future verification code locally. You can paste the Base32 setup key or the complete otpauth:// link.")
                    Text("The vault is readable only by your macOS account and never invokes Keychain.")
                }.font(.caption).foregroundStyle(.secondary)
                if !securityError.isEmpty { Label(securityError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption) }
                Text("Credentials are saved when you choose Save & Connect.").font(.caption).foregroundStyle(.secondary)
            }.padding().tabItem { Label("Security", systemImage: "lock.shield") }
            Form {
                Toggle("Reconnect automatically", isOn: $model.reconnectAutomatically)
                Toggle("Start with inspector visible", isOn: $model.showInspector)
                Toggle("Enable remote audio", isOn: $model.audioEnabled)
            }.padding().tabItem { Label("General", systemImage: "gearshape") }
            }
            Divider()
            HStack {
                Text(savedMessage).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save & Connect") {
                    if saveCredentials() { model.saveDevice(); dismiss(); model.connect() }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || URL(string: model.device.endpoint)?.scheme != "https")
            }.padding()
        }
    }
    @discardableResult private func saveCredentials() -> Bool {
        securityError = ""
        guard let normalizedSecret = TOTP.secret(from: totpSecret) else {
            securityError = "That is not a setup key. A six-digit verification code cannot generate future codes. Paste the Base32 setup key or otpauth link."
            return false
        }
        do {
            try CredentialVault.save(password: password, totpSecret: normalizedSecret)
            UserDefaults.standard.set(true, forKey: "hasSavedCredentials")
            model.hasSavedPassword = true
            totpSecret = normalizedSecret
            savedMessage = "Password and automatic 2FA saved in private local vault"
            return true
        } catch { securityError = error.localizedDescription; return false }
    }
}
