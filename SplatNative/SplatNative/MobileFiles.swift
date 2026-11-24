// SplatNative - MobileFiles.swift
// iOS / iPadOS: the game files live in the app's Documents folder (visible in the Files
// app under On My iPad), and the engine is linked into the app itself.
#if os(iOS)
import Combine
import Foundation

struct GameFile: Identifiable {
    let id: String
    /// File names this slot accepts, first one is what imports are renamed to.
    let names: [String]
    var optional = false

    var url: URL? {
        names.map { Paths.documents.appending(path: $0) }.first { url in
            var dir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) else { return false }
            return !dir.boolValue || containsNCA(url)
        }
    }

    var status: String {
        guard let url else { return optional ? "none" : "missing" }
        guard let size = fileSize(url), !url.hasDirectoryPath, url.pathExtension != "" else { return "found" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

let gameFiles = [
    GameFile(id: "Base game", names: ["base.xci", "base.nsp"]),
    GameFile(id: "Update", names: ["update.nsp"]),
    GameFile(id: "Side Order (DLC)", names: ["dlc.nsp"], optional: true),
    GameFile(id: "Console keys", names: ["prod.keys"]),
    GameFile(id: "Firmware", names: ["Firmware"]),
]

final class Files: ObservableObject {
    @Published var present: [String: URL] = [:]
    @Published var copying: String?
    @Published var error: String?

    var ready: Bool { gameFiles.allSatisfy { $0.optional || present[$0.id] != nil } }

    /// Also renames dumps dropped into Documents through the Files app.
    func scan() {
        let fm = FileManager.default
        let known = Set(gameFiles.flatMap(\.names))
        for n in (try? fm.contentsOfDirectory(atPath: Paths.documents.path)) ?? [] where !known.contains(n) {
            let url = Paths.documents.appending(path: n)
            guard let name = Files.target(for: url), name != n else { continue }
            let dest = Paths.documents.appending(path: name)
            if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: url, to: dest) }
        }
        present = Dictionary(uniqueKeysWithValues: gameFiles.compactMap { f in f.url.map { (f.id, $0) } })
    }

    func copy(_ urls: [URL]) {
        error = nil
        Task.detached(priority: .userInitiated) {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let name = Files.target(for: url) ?? url.lastPathComponent
                await MainActor.run { self.copying = name }
                let dest = Paths.documents.appending(path: name)
                do {
                    if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                    try FileManager.default.copyItem(at: url, to: dest)
                } catch {
                    let message = "\(url.lastPathComponent): \(error.localizedDescription)"
                    await MainActor.run { self.error = message }
                }
            }
            await MainActor.run {
                self.copying = nil
                self.scan()
            }
        }
    }

    nonisolated static func target(for url: URL) -> String? {
        let n = url.lastPathComponent.lowercased()
        if n.hasSuffix(".keys") { return n.contains("title") ? "title.keys" : "prod.keys" }
        if url.hasDirectoryPath || n.hasPrefix("firmware") { return "Firmware" }
        let ext = n.hasSuffix(".xci") ? "xci" : "nsp"
        switch packageKind(url) {
        case .base: return "base.\(ext)"
        case .update: return "update.nsp"
        case .dlc: return "dlc.nsp"
        case .otherGame, nil: return nil
        }
    }
}

/// The engine (nxhost built for aarch64-apple-ios) exports this when it is linked into the
/// app. It reads config.json and the files from Documents and takes over the window.
func startLinkedEngine() -> String? {
    let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
    guard let sym = dlsym(defaultHandle, "splatnative_start_game") else {
        return "This build doesn't contain the game engine yet. Link nxhost for iOS into the app to play here; your files and settings are ready in Documents."
    }
    typealias Start = @convention(c) () -> Int32
    let code = unsafeBitCast(sym, to: Start.self)()
    return code == 0 ? nil : "The engine couldn't start (code \(code)). See work/nxhost.log in Files."
}
#endif
