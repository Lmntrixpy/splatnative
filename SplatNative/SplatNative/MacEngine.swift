// SplatNative - MacEngine.swift
// macOS: checks the splatnative checkout, prepares the game code (s3tool extract →
// nxpatch rewrite) and runs nxhost as a child process.
#if os(macOS)
import AppKit
import Combine
import Foundation

/// A bundled copy (Contents/MacOS) wins over the checkout's build output.
func tool(_ name: String, in folder: URL) -> URL {
    let bundled = Bundle.main.bundleURL.appending(path: "Contents/MacOS/\(name)")
    if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
    let own = folder.appending(path: "target/release/\(name)")
    if FileManager.default.isExecutableFile(atPath: own.path) { return own }
    return folder.appending(path: "third_party/mush8/target/release/\(name)")
}

let exefsDir = "work/exefs"
let patchedDir = "work/patched"
let shaderIndex = "work/shader_cache.noindex/heap-segments-v2/index.tsv"

/// The update file the extracted ExeFS came from (its size), written after each extract.
func updateSource(_ s: Settings) -> String {
    let url = resolve(s.update, in: s.folderURL).resolvingSymlinksInPath()
    return "\(fileSize(url) ?? 0)"
}

func extractedSource(in folder: URL) -> String? {
    try? String(contentsOf: folder.appending(path: "\(exefsDir).source"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The main NSO's build ID (header 0x40, 20 bytes): the name of its Nextendo IPS patches.
func buildID(in folder: URL) -> String? {
    guard let h = try? FileHandle(forReadingFrom: folder.appending(path: "\(exefsDir)/main")) else { return nil }
    defer { try? h.close() }
    guard let d = try? h.read(upToCount: 0x60), d.count >= 0x54, d.prefix(4) == Data("NSO0".utf8) else { return nil }
    return d[0x40..<0x54].map { String(format: "%02X", $0) }.joined()
}

/// The Prelude-Nextendo patches for this build (cert bypass, peer name), in the order the
/// existing work/patched was built with.
func codePatches(in folder: URL) -> [String] {
    guard let id = buildID(in: folder) else { return [] }
    return ["s3certbypass", "s3peername"].compactMap { name in
        let rel = "third_party/Prelude-Nextendo/romfs/sd/atmosphere/exefs_patches/\(name)/\(id).ips"
        return FileManager.default.fileExists(atPath: folder.appending(path: rel).path) ? rel : nil
    }
}

private var stampCache: [String: String] = [:]

func expectedPatchStamp(in folder: URL) -> String? {
    let exe = tool("nxpatch", in: folder)
    guard FileManager.default.isExecutableFile(atPath: exe.path) else { return nil }
    let patches = codePatches(in: folder)
    let args = ["stamp"] + patches.flatMap { ["--patch", $0] }
    let modified = ([exe.path] + patches.map { folder.appending(path: $0).path }).map { path in
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date).map { "\($0.timeIntervalSince1970)" } ?? ""
    }
    let key = ([folder.path] + args + modified).joined(separator: "\n")
    if let cached = stampCache[key] { return cached }
    let p = Process()
    let pipe = Pipe()
    p.executableURL = exe
    p.arguments = args
    p.currentDirectoryURL = folder
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return nil }
    p.waitUntilExit()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    stampCache[key] = out
    return out
}

func gameCodeReady(in folder: URL) -> Bool {
    let made = try? String(contentsOf: folder.appending(path: "\(patchedDir)/nxpatch.stamp"), encoding: .utf8)
    guard let made, let expected = expectedPatchStamp(in: folder) else { return false }
    return made.trimmingCharacters(in: .whitespacesAndNewlines) == expected
}

struct Check: Identifiable {
    let id: String
    let ok: Bool
    let detail: String
    var optional = false
}

func checks(_ s: Settings) -> [Check] {
    let fm = FileManager.default
    let f = s.folderURL
    func file(_ path: String) -> Bool { !path.isEmpty && fm.fileExists(atPath: resolve(path, in: f).path) }
    let engine = ["nxhost", "nxpatch", "s3tool"].filter { !fm.isExecutableFile(atPath: tool($0, in: f).path) }
    let extracted = fm.fileExists(atPath: f.appending(path: "\(exefsDir)/main").path)
        && fm.fileExists(atPath: f.appending(path: "\(exefsDir)/main.npdm").path)
        && (extractedSource(in: f).map { $0 == updateSource(s) } ?? true)
    let shaders = fm.fileExists(atPath: f.appending(path: shaderIndex).path)
    return [
        Check(id: "Base game", ok: file(s.base), detail: file(s.base) ? s.base : "not found"),
        Check(id: "Update", ok: file(s.update), detail: file(s.update) ? s.update : "not found"),
        Check(id: "Side Order (DLC)", ok: file(s.dlc), detail: file(s.dlc) ? s.dlc : "none", optional: true),
        Check(id: "Console keys", ok: file(s.keys), detail: file(s.keys) ? s.keys : "not found"),
        Check(id: "Firmware", ok: file(s.firmware), detail: file(s.firmware) ? s.firmware : "not found"),
        Check(id: "Engine", ok: engine.isEmpty, detail: engine.isEmpty ? "nxhost, nxpatch, s3tool" : "build missing: \(engine.joined(separator: ", "))"),
        Check(id: "Game code for this Mac", ok: extracted && gameCodeReady(in: f), detail: patchedDir),
        Check(id: "Precompiled shaders", ok: shaders, detail: shaders ? "work/shader_cache.noindex" : "compiled while playing", optional: true),
    ]
}

/// Runs the tool chain one step at a time and shows the last output line.
final class Preparer: ObservableObject {
    @Published var running = false
    @Published var line = ""
    @Published var error: String?
    private var current: Process?

    func prepare(_ s: Settings, done: @escaping () -> Void) {
        let f = s.folderURL
        let fm = FileManager.default
        var steps: [Step] = []
        let source = updateSource(s)
        if extractedSource(in: f).map({ $0 != source }) ?? false || !fm.fileExists(atPath: f.appending(path: "\(exefsDir)/main").path) {
            steps.append(Step(exe: tool("s3tool", in: f), args: { ["--keys", s.keys, "extract", "--base", s.base, "--update", s.update, "--out", "work"] }, after: {
                try? source.write(to: f.appending(path: "\(exefsDir).source"), atomically: true, encoding: .utf8)
            }))
        }
        steps.append(Step(exe: tool("nxpatch", in: f), args: {
            ["rewrite", "--out", patchedDir, "\(exefsDir)/main", "\(exefsDir)/sdk"] + codePatches(in: f).flatMap { ["--patch", $0] }
        }, skip: { gameCodeReady(in: f) }))
        run(steps[...], folder: f, done: done)
    }

    func precompile(_ s: Settings, done: @escaping () -> Void) {
        let f = s.folderURL
        run([Step(exe: tool("nxhost", in: f), args: { gameArguments(s) + ["--precompile"] }, env: s.environment)][...], folder: f, done: done)
    }

    func cancel() { current?.terminate() }

    struct Step {
        let exe: URL
        let args: () -> [String]
        var env: [String: String] = [:]
        var skip: () -> Bool = { false }
        var after: () -> Void = {}
    }

    private func run(_ steps: ArraySlice<Step>, folder: URL, done: @escaping () -> Void) {
        running = true
        error = nil
        guard let step = steps.first else {
            running = false
            line = ""
            current = nil
            done()
            return
        }
        if step.skip() {
            run(steps.dropFirst(), folder: folder, done: done)
            return
        }
        let p = Process()
        p.executableURL = step.exe
        p.arguments = step.args()
        p.currentDirectoryURL = folder
        p.environment = ProcessInfo.processInfo.environment.merging(step.env) { $1 }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            guard let last = String(decoding: h.availableData, as: UTF8.self).split(separator: "\n").last else { return }
            let text = String(last)
            Task { @MainActor in self.line = text }
        }
        let name = step.exe.lastPathComponent
        p.terminationHandler = { p in
            let status = p.terminationStatus, reason = p.terminationReason
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                if status == 0 {
                    step.after()
                    self.run(steps.dropFirst(), folder: folder, done: done)
                } else {
                    self.running = false
                    self.current = nil
                    self.error = reason == .uncaughtSignal ? "\(name) was stopped" : "\(name) failed: \(self.line)"
                    done()
                }
            }
        }
        line = "\(name) \(p.arguments?.first ?? "")…"
        do {
            try p.run()
            current = p
        } catch {
            running = false
            self.error = "Could not run \(name): \(error.localizedDescription)"
            done()
        }
    }
}

func gameArguments(_ s: Settings) -> [String] {
    var a = ["--patched", patchedDir, "--npdm", "\(exefsDir)/main.npdm",
             "--keys", s.keys, "--base", s.base, "--update", s.update, "--firmware", s.firmware]
    if !s.dlc.isEmpty, FileManager.default.fileExists(atPath: resolve(s.dlc, in: s.folderURL).path) { a += ["--dlc", s.dlc] }
    return a
}

/// The running game. nxhost opens its own window; the launcher stays open to stop it.
final class GameSession: ObservableObject {
    @Published var running = false
    @Published var message: String?
    private var process: Process?

    func start(_ s: Settings) {
        guard process == nil else { return }
        message = nil
        let fm = FileManager.default
        let prev = Paths.log.deletingPathExtension().appendingPathExtension("prev.log")
        try? fm.createDirectory(at: Paths.log.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: prev)
        try? fm.moveItem(at: Paths.log, to: prev)
        fm.createFile(atPath: Paths.log.path, contents: nil)
        guard let log = try? FileHandle(forWritingTo: Paths.log) else {
            message = "Could not write \(Paths.log.path)"
            return
        }
        let p = Process()
        p.executableURL = tool("nxhost", in: s.folderURL)
        p.arguments = gameArguments(s)
        p.currentDirectoryURL = s.folderURL
        p.environment = ProcessInfo.processInfo.environment.merging(s.environment) { $1 }
        p.standardOutput = log
        p.standardError = log
        p.terminationHandler = { p in
            let status = p.terminationStatus, reason = p.terminationReason
            try? log.close()
            Task { @MainActor in
                self.process = nil
                self.running = false
                if reason == .exit && status != 0 {
                    self.message = "The game quit with code \(status): \(lastLogLine() ?? "see the log")"
                } else if reason == .uncaughtSignal && status != SIGTERM {
                    self.message = "The game crashed (signal \(status)). See the log."
                }
                NSApp.activate()
            }
        }
        do {
            try p.run()
            process = p
            running = true
        } catch {
            message = "Could not start the game: \(error.localizedDescription)"
        }
    }

    func stop() { process?.terminate() }
}

func lastLogLine() -> String? {
    guard let h = try? FileHandle(forReadingFrom: Paths.log) else { return nil }
    defer { try? h.close() }
    let end = (try? h.seekToEnd()) ?? 0
    try? h.seek(toOffset: end > 4096 ? end - 4096 : 0)
    let text = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
    return text.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(String.init)
}

/// Fills empty game file settings from what's in the folder.
func adopt(_ found: FoundFiles, into s: Settings, overwrite: Bool) {
    func set(_ path: inout String, _ value: String?) {
        if let value, overwrite || path.isEmpty || !FileManager.default.fileExists(atPath: resolve(path, in: s.folderURL).path) { path = value }
    }
    set(&s.base, found.base)
    set(&s.update, found.update)
    set(&s.dlc, found.dlc)
    set(&s.keys, found.keys)
    set(&s.firmware, found.firmware)
}
#endif
