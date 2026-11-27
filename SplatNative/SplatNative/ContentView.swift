// SplatNative - ContentView.swift
// The launcher: game file status, settings pages and Play.
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

struct LauncherView: View {
    @StateObject private var s = Settings()
    @StateObject private var sys = SystemInfo()
    @State private var error: String?
    @State private var launching = false
    /// A refusal from Nextendo's online gate is shown once; Play again starts anyway.
    @State private var shownRefusal: String?
    #if os(macOS)
    @StateObject private var prep = Preparer()
    @StateObject private var game = GameSession()
    @State private var tick = 0
    @State private var pageOpen = false
    #else
    @StateObject private var files = Files()
    @State private var picking = false
    @Environment(\.scenePhase) private var phase
    #endif

    var body: some View {
        #if os(macOS)
        macBody
        #else
        mobileBody
        #endif
    }

    // MARK: - Pages

    var settingsList: some View {
        Group {
            Section {
                NavigationLink { multiplayerPage } label: {
                    CategoryLabel(title: "Multiplayer", icon: "person.2.fill", color: .green, value: modeName)
                }
                NavigationLink { playerPage } label: {
                    CategoryLabel(title: "Player", icon: "person.crop.circle.fill", color: .purple, value: s.nickname.isEmpty ? nil : s.nickname)
                }
            }
            Section {
                NavigationLink { graphicsPage } label: {
                    CategoryLabel(title: "Graphics", icon: "display", color: .blue, value: consoleName)
                }
                NavigationLink { controlsPage } label: {
                    CategoryLabel(title: "Audio & Controls", icon: "gamecontroller.fill", color: .pink, value: nil)
                }
            }
            Section {
                NavigationLink { devicePage } label: {
                    CategoryLabel(title: "Device", icon: deviceIcon, color: lowMemory ? .orange : .gray, value: bytes(sys.memory))
                }
            }
        }
    }

    var modeName: String {
        switch s.network {
        case "lan": "LAN"
        case "lanplay": "Lan-Play"
        case "wireless": "Wireless"
        case "nextendo": s.nextendoName.isEmpty ? "Nextendo" : s.nextendoName
        default: "Off"
        }
    }

    var consoleName: String {
        switch s.console {
        case "handheld": "Handheld"
        case "4k": "4K"
        default: "1080p"
        }
    }

    var multiplayerPage: some View {
        CategoryPage(title: "Multiplayer") {
            Section {
                Picker("Mode", selection: $s.network) {
                    Text("Off").tag("off")
                    Text("LAN").tag("lan")
                    Text("Lan-Play").tag("lanplay")
                    Text("Wireless (nearby)").tag("wireless")
                    Text("Nextendo").tag("nextendo")
                }
                switch s.network {
                case "lan":
                    Picker("Network", selection: $s.lanInterface) {
                        Text("Automatic").tag("")
                        ForEach(sys.interfaces, id: \.self) { n in Text("\(n.name) · \(n.ip)").tag(n.name) }
                    }
                case "lanplay":
                    TextField("Server", text: $s.lanPlayServer, prompt: Text("host:port"))
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        #endif
                case "nextendo":
                    NextendoSignIn(pid: $s.nextendoPid, name: $s.nextendoName)
                default:
                    EmptyView()
                }
            } footer: {
                Text(multiplayerNote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var multiplayerNote: String {
        switch s.network {
        case "lan": "Switch consoles and SplatNative players on the same network can join"
        case "lanplay": "Players on the same Lan-Play server can join"
        case "wireless": "Nearby SplatNative players can join local play (keep Wi-Fi on)"
        case "nextendo": "Online play on the Nextendo network. Needs a Nextendo account with a confirmed e-mail and linked Discord"
        default: "The game runs offline"
        }
    }

    var playerPage: some View {
        CategoryPage(title: "Player") {
            Section {
                TextField("Account name", text: $s.nickname, prompt: Text("Player"))
                    .onChange(of: s.nickname) { _, n in if n.count > 10 { s.nickname = String(n.prefix(10)) } }
                Picker("Game language", selection: $s.language) {
                    ForEach(gameLanguages, id: \.tag) { Text($0.name).tag($0.tag) }
                }
            } footer: {
                Text("The account name is the console user, 10 characters max. Your in-game name is chosen in the game itself")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var graphicsPage: some View {
        CategoryPage(title: "Graphics") {
            Section {
                Picker("Console mode", selection: $s.console) {
                    Text("Docked (1080p)").tag("docked")
                    #if os(macOS)
                    Text("Docked (4K)").tag("4k")
                    #endif
                    Text("Handheld (720p)").tag("handheld")
                }
                Picker("Screen", selection: $s.fillScreen) {
                    Text("16:9").tag(false)
                    Text("Fill screen").tag(true)
                }
                if s.fillScreen {
                    Picker("HUD", selection: $s.hudAtEdges) {
                        Text("Screen edges").tag(true)
                        Text("Centered").tag(false)
                    }
                }
                PercentSlider(title: "HUD size", value: $s.hudScale, range: 0.5...1.5, step: 0.05)
            } footer: {
                Text("Handheld is lighter on the GPU and battery").font(.caption).foregroundStyle(.secondary)
            }
            #if os(iOS)
            Section {
                Picker("Textures", selection: $s.textures) {
                    Text("Auto").tag("auto")
                    Text("Full").tag("0")
                    Text("Low").tag("1")
                    Text("Very low").tag("2")
                }
            } footer: {
                Text("Lower uses less memory but looks blurrier").font(.caption).foregroundStyle(.secondary)
            }
            #endif
            Section {
                Toggle("Prewarm pipelines", isOn: $s.prewarm)
                Toggle(isOn: $s.backgroundCompile) {
                    labeled("Background shader compiling", "Off waits for every shader: no pop-in, but stutters")
                }
                #if os(macOS)
                HStack {
                    labeled("Precompile all shaders", "Takes a while, but the first match won't stutter")
                    Spacer()
                    if prep.running {
                        ProgressView().controlSize(.small)
                        Button("Stop") { prep.cancel() }
                    } else {
                        Button("Precompile") { prep.precompile(s) { tick += 1 } }
                            .disabled(!checks(s).filter { $0.id != "Precompiled shaders" }.allSatisfy { $0.ok || $0.optional } || game.running)
                    }
                }
                if prep.running { Text(prep.line).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle) }
                #endif
            } footer: {
                Text("Builds graphics pipelines at startup").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var controlsPage: some View {
        CategoryPage(title: "Audio & Controls") {
            Section {
                Toggle("Spatial audio", isOn: $s.spatial)
            }
            Section {
                Toggle("Vibration", isOn: $s.rumble)
                if s.rumble {
                    PercentSlider(title: "Rumble cutoff", value: $s.rumbleMin, range: 0...0.9, step: 0.05)
                }
            } footer: {
                if s.rumble {
                    Text("Weaker rumble is ignored, which stops the buzz on Xbox and PlayStation controllers")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(isOn: $s.mouseAim) {
                    labeled("Aim with mouse and keys", "A virtual motion sensor: the mouse (once captured) and I/K tilt the camera like gyro aiming")
                }
                if s.mouseAim {
                    Toggle(isOn: $s.clickCapture) {
                        labeled("Click captures the mouse", "Esc releases it. Off: clicks tap the touchscreen")
                    }
                    HStack {
                        Text("Mouse sensitivity")
                        Slider(value: $s.mouseSensitivity, in: 0.0005...0.01, step: 0.0005)
                        Text(String(format: "%.1f×", s.mouseSensitivity / 0.003)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Key tilt speed")
                        Slider(value: $s.keyGyroRate, in: 0.25...4, step: 0.25)
                        Text(String(format: "%.1f×", s.keyGyroRate / 1.5)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: $s.motion) {
                    labeled("Controller motion sensors", "Gyro of a real controller (Switch Pro, DualSense) instead of the virtual one")
                }
                Toggle("Touchscreen", isOn: $s.touchscreen)
                #if os(macOS)
                Picker(selection: $s.padDriver) {
                    Text("Apple").tag("apple")
                    Text("SDL").tag("sdl")
                } label: {
                    labeled("Gamepad driver", "SDL supports more controllers, Apple follows System Settings remapping")
                }
                #endif
            } footer: {
                Text("Keyboard: WASD move, Space jump, Shift swim, R or left click shoot, E sub weapon, F special")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    var deviceIcon: String {
        #if os(macOS)
        "desktopcomputer"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad.landscape" : "iphone"
        #endif
    }

    var lowMemory: Bool {
        #if os(macOS)
        sys.memory < 4 << 30
        #else
        sys.memory < 7 << 29
        #endif
    }

    var devicePage: some View {
        CategoryPage(title: "Device") {
            Section {
                HStack {
                    Text("Memory available")
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(bytes(sys.memory)).foregroundStyle(.secondary).monospacedDigit()
                        if lowMemory {
                            Text(lowMemoryHint).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            gameFilesSection
        }
    }

    /// In Nextendo mode, signs the game in first: fresh tokens, then Nextendo's online gate.
    /// Other modes start right away.
    func withNextendo(_ start: @escaping ([String: String]) -> Void) {
        guard s.network == "nextendo" else {
            start([:])
            return
        }
        guard !launching else { return }
        launching = true
        Task { @MainActor in
            defer { launching = false }
            do {
                let login = try await Nextendo.gameLogin()
                s.nextendoPid = login.pid
                s.nextendoName = login.name
                try? s.save()
                let gate = await Nextendo.onlineGate(login.token)
                let refusal = gate.problem.map { "\(login.pid) \($0)" }
                if let problem = gate.problem, shownRefusal != refusal {
                    shownRefusal = refusal
                    error = problem + " Press Play again to start anyway: online play won't work until then."
                    return
                }
                shownRefusal = nil
                start(Nextendo.environment(login, gate: gate))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    var lowMemoryHint: String {
        #if os(macOS)
        "4 GB of free memory is recommended"
        #else
        "3.5 GB is recommended: close other apps"
        #endif
    }
}

// MARK: - macOS

#if os(macOS)
extension LauncherView {
    var macBody: some View {
        let _ = tick
        let list = checks(s)
        let ready = list.allSatisfy { $0.ok || $0.optional }
        let canPrepare = !s.folder.isEmpty && list.filter { ["Base game", "Update", "Console keys", "Firmware", "Engine"].contains($0.id) }.allSatisfy(\.ok)
        return VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("SplatNative").font(.title2.weight(.semibold))
                    Text("Splatoon 3 on Apple silicon").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            NavigationStack {
                Form {
                    if !ready { gameFilesSection }
                    settingsList
                }
                .formStyle(.grouped)
                .onAppear { pageOpen = false }
                .onDisappear { pageOpen = true }
            }
            if let e = error ?? prep.error ?? game.message {
                Text(e).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center).textSelection(.enabled)
            }
            if game.running {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Playing").foregroundStyle(.secondary)
                    Spacer()
                    Button("Show log") { NSWorkspace.shared.open(Paths.log) }
                    Button("Stop game", role: .destructive) { game.stop() }
                }
            } else if prep.running {
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(prep.line).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                    Button("Cancel") { prep.cancel() }
                }
            } else if ready {
                Button(action: play) {
                    Text(launching ? "Signing in to Nextendo…" : "Play").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
                .disabled(launching)
                .keyboardShortcut(pageOpen ? nil : .defaultAction)
            } else {
                Button { prep.prepare(s) { tick += 1 } } label: {
                    Text("Prepare game code").frame(maxWidth: .infinity)
                }
                .controlSize(.large).buttonStyle(.borderedProminent)
                .disabled(pageOpen || !canPrepare)
                Text(canPrepare ? "Extracts and rewrites the game code for this Mac (takes a few minutes)"
                                : "Choose your splatnative folder with the game files, keys and firmware, and build the engine")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(width: 520, height: 720)
        .onAppear(perform: autodetect)
        .onChange(of: s.folder) { autodetect() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in tick += 1 }
    }

    var gameFilesSection: some View {
        let list = checks(s)
        return Section("Game data") {
            HStack {
                Text(s.folder.isEmpty ? "No folder chosen" : s.folder).lineLimit(1).truncationMode(.head)
                    .foregroundStyle(s.folder.isEmpty ? .secondary : .primary)
                Spacer()
                Button("Choose…", action: chooseFolder).disabled(prep.running || game.running)
            }
            ForEach(list) { c in CheckRow(title: c.id, ok: c.ok, optional: c.optional, detail: c.detail) }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose your splatnative folder (with rom/ and work/)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        s.folder = url.path
        adopt(discoverGameFiles(in: url), into: s, overwrite: true)
        tick += 1
    }

    func autodetect() {
        guard !s.folder.isEmpty else { return }
        adopt(discoverGameFiles(in: s.folderURL), into: s, overwrite: false)
        tick += 1
    }

    func play() {
        error = nil
        guard checks(s).allSatisfy({ $0.ok || $0.optional }) else {
            error = "Your game files changed. Prepare again before playing."
            tick += 1
            return
        }
        if s.network == "lanplay" && s.lanPlayServer.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Enter a Lan-Play server (host:port)"
            return
        }
        try? s.save()
        withNextendo { game.start(s, extra: $0) }
    }
}
#endif

// MARK: - iOS / iPadOS

#if os(iOS)
extension LauncherView {
    var mobileBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Text("SplatNative").font(.largeTitle.weight(.bold))
                if files.ready && files.copying == nil {
                    if let error { Text(error).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
                    Button(action: play) {
                        Text(launching ? "Signing in…" : "Play").font(.title3.weight(.semibold)).frame(maxWidth: 220)
                    }
                    .disabled(launching)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                } else {
                    importView
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            NavigationStack {
                Form {
                    if !files.ready { gameFilesSection }
                    settingsList
                }
            }
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { files.copy(urls) }
        }
        .onAppear { files.scan() }
        .onChange(of: phase) { _, p in if p == .active { files.scan() } }
    }

    var gameFilesSection: some View {
        Section {
            ForEach(gameFiles) { f in
                CheckRow(title: f.id, ok: files.present[f.id] != nil, optional: f.optional, detail: f.status)
            }
            Button("Import game files…") { picking = true }.disabled(files.copying != nil)
        } header: {
            Text("Game files")
        } footer: {
            Text("Or copy them into Files → On My iPad → SplatNative").font(.caption)
        }
    }

    @ViewBuilder var importView: some View {
        VStack(spacing: 12) {
            if let name = files.copying {
                ProgressView()
                Text("Copying \(name)…").font(.callout)
            } else {
                Button("Import game files") { picking = true }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                Text("Import your prod.keys, the base game (.xci or .nsp), the update .nsp and the Firmware folder")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let e = files.error { Text(e).foregroundStyle(.red).font(.callout).multilineTextAlignment(.center) }
        }
    }

    func play() {
        error = nil
        if s.network == "lanplay" && s.lanPlayServer.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Enter a Lan-Play server (host:port)"
            return
        }
        s.base = files.present["Base game"]?.lastPathComponent ?? "base.xci"
        s.update = "update.nsp"
        s.dlc = files.present["Side Order (DLC)"] == nil ? "" : "dlc.nsp"
        s.keys = "prod.keys"
        s.firmware = "Firmware"
        do { try s.save() } catch {
            self.error = "Could not save settings: \(error.localizedDescription)"
            return
        }
        withNextendo { extra in
            for (k, v) in s.environment.merging(extra, uniquingKeysWith: { $1 }) { setenv(k, v, 1) }
            error = startLinkedEngine()
        }
    }
}
#endif

#Preview {
    LauncherView()
}
