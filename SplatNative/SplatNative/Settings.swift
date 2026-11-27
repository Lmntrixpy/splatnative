// SplatNative - Settings.swift
// Launcher settings, saved as JSON and handed to nxhost as NX_* environment variables
// (macOS) or through config.json in the app's Documents folder (iOS / iPadOS).
import Combine
import Foundation

nonisolated enum Paths {
    #if os(macOS)
    static let support = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/SplatNative")
    static let config = support.appending(path: "config.json")
    static let log = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/SplatNative.log")
    #else
    static let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    static let config = documents.appending(path: "config.json")
    static let log = documents.appending(path: "work/nxhost.log")
    #endif
}

final class Settings: ObservableObject {
    // Game files. On macOS these are paths relative to `folder` (the splatnative checkout),
    // on iOS file names inside Documents.
    @Published var folder = ""
    @Published var base = ""
    @Published var update = ""
    @Published var dlc = ""
    @Published var keys = ""
    @Published var firmware = ""

    @Published var network = "off"
    @Published var lanInterface = ""
    @Published var lanPlayServer = ""
    @Published var nickname = ""
    @Published var nextendoPid: UInt64 = 0
    @Published var nextendoName = ""
    @Published var language = ""

    @Published var console = "docked"
    @Published var fillScreen = true
    @Published var hudAtEdges = true
    @Published var hudScale = 1.0
    @Published var textures = "auto"
    @Published var prewarm = true
    @Published var backgroundCompile = true

    @Published var spatial = true
    @Published var rumble = true
    @Published var rumbleMin = 0.45
    @Published var padDriver = "apple"
    @Published var motion = false
    @Published var touchscreen = true
    @Published var mouseAim = true
    @Published var clickCapture = true
    @Published var mouseSensitivity = 0.003
    @Published var keyGyroRate = 1.5

    private var extra: [String: Any] = [:]
    private var autosave: AnyCancellable?

    init() {
        defer {
            autosave = objectWillChange
                .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
                .sink { [weak self] in try? self?.save() }
        }
        guard let data = try? Data(contentsOf: Paths.config),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        extra = j
        folder = j["folder"] as? String ?? ""
        base = j["base"] as? String ?? ""
        update = j["update"] as? String ?? ""
        dlc = j["dlc"] as? String ?? ""
        keys = j["keys"] as? String ?? ""
        firmware = j["firmware"] as? String ?? ""
        network = j["network"] as? String ?? "off"
        nextendoPid = (j["nextendo_pid"] as? NSNumber)?.uint64Value ?? 0
        nextendoName = j["nextendo_name"] as? String ?? ""
        lanInterface = j["lan_interface"] as? String ?? ""
        lanPlayServer = j["lanplay_server"] as? String ?? ""
        nickname = j["nickname"] as? String ?? ""
        language = j["language"] as? String ?? ""
        console = j["console"] as? String ?? (j["handheld"] as? Bool == true ? "handheld" : "docked")
        fillScreen = j["aspect"] as? String != "16:9"
        hudAtEdges = j["hud"] as? String != "center"
        hudScale = j["hud_scale"] as? Double ?? 1.0
        textures = j["textures"] as? String ?? "auto"
        prewarm = j["prewarm_pipelines"] as? Bool ?? true
        backgroundCompile = j["background_compile"] as? Bool ?? true
        spatial = j["spatial_audio"] as? Bool ?? true
        rumble = j["rumble"] as? Bool ?? true
        rumbleMin = j["rumble_min"] as? Double ?? 0.45
        padDriver = j["gamepad_driver"] as? String ?? "apple"
        motion = j["motion_controls"] as? Bool ?? false
        touchscreen = j["touchscreen"] as? Bool ?? true
        mouseAim = j["mouse_aim"] as? Bool ?? true
        clickCapture = j["click_capture"] as? Bool ?? true
        mouseSensitivity = j["mouse_sensitivity"] as? Double ?? 0.003
        keyGyroRate = j["key_gyro_rate"] as? Double ?? 1.5
    }

    var folderURL: URL { URL(fileURLWithPath: folder) }

    /// Unknown keys are kept, so config.json can also carry settings nxhost reads that the
    /// launcher has no control for.
    func save() throws {
        var j = extra
        j["folder"] = folder
        j["base"] = base
        j["update"] = update
        j["dlc"] = dlc
        j["keys"] = keys
        j["firmware"] = firmware
        j["network"] = network
        j["lan_interface"] = lanInterface
        j["lanplay_server"] = lanPlayServer
        j["nickname"] = nickname
        j["nextendo_pid"] = NSNumber(value: nextendoPid)
        j["nextendo_name"] = nextendoName
        j["player_name"] = nickname
        j["language"] = language
        j["console"] = console
        j["handheld"] = console == "handheld"
        j["aspect"] = fillScreen ? "fill" : "16:9"
        j["hud"] = hudAtEdges ? "edges" : "center"
        j["hud_scale"] = hudScale
        j["textures"] = textures
        j["prewarm_pipelines"] = prewarm
        j["background_compile"] = backgroundCompile
        j["spatial_audio"] = spatial
        j["rumble"] = rumble
        j["rumble_min"] = rumbleMin
        j["gamepad_driver"] = padDriver
        j["motion_controls"] = motion
        j["touchscreen"] = touchscreen
        j["mouse_aim"] = mouseAim
        j["click_capture"] = clickCapture
        j["mouse_sensitivity"] = mouseSensitivity
        j["key_gyro_rate"] = keyGyroRate
        try FileManager.default.createDirectory(at: Paths.config.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: j, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: Paths.config, options: .atomic)
    }

    /// The NX_* variables nxhost reads at startup.
    var environment: [String: String] {
        var env: [String: String] = [:]
        env["NX_NET"] = network
        switch network {
        case "lan":
            env["NX_LAN"] = "1"
            if !lanInterface.isEmpty { env["NX_LAN_IF"] = lanInterface }
        case "lanplay":
            env["NX_LANPLAY_SERVER"] = lanPlayServer.trimmingCharacters(in: .whitespaces)
        case "nextendo":
            env["NX_NEXTENDO_PID"] = String(nextendoPid)
        default:
            break
        }
        let name = nickname.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { env["NX_NICKNAME"] = String(name.prefix(10)) }
        if !language.isEmpty { env["NX_LANGUAGE"] = language }
        switch console {
        case "handheld": env["NX_HANDHELD"] = "1"
        case "4k": env["NX_4K"] = "1"
        default: break
        }
        if fillScreen { env["NX_ASPECT"] = "auto" }
        if !hudAtEdges { env["NX_HUD"] = "center" }
        if hudScale != 1 { env["NX_HUD_SCALE"] = String(hudScale) }
        if prewarm { env["NX_PREWARM"] = "1" }
        if !backgroundCompile { env["NX_SYNC_SHADERS"] = "1" }
        if !spatial { env["NX_SPATIAL"] = "0" }
        if !rumble { env["NX_RUMBLE"] = "0" }
        env["NX_RUMBLE_MIN"] = String(rumbleMin)
        env["NX_PAD_DRIVER"] = padDriver
        env["NX_MOTION"] = motion ? "1" : "0"
        if !touchscreen { env["NX_TOUCHSCREEN"] = "0" }
        if !mouseAim { env["NX_KEY_GYRO"] = "0" }
        if !clickCapture { env["NX_CLICK_CAPTURE"] = "0" }
        env["NX_MOUSE_SENS"] = String(mouseSensitivity)
        env["NX_KEY_GYRO_RATE"] = String(keyGyroRate)
        return env
    }
}

let gameLanguages: [(tag: String, name: String)] = [
    ("", "Same as the device"),
    ("de", "Deutsch"),
    ("en-US", "English (US)"),
    ("en-GB", "English (UK)"),
    ("fr", "Français"),
    ("es", "Español"),
    ("it", "Italiano"),
    ("nl", "Nederlands"),
    ("ja", "日本語"),
]
