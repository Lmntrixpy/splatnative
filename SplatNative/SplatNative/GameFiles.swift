// SplatNative - GameFiles.swift
// Recognises the user's own Splatoon 3 dumps and reports device facts (memory, network).
import Combine
import Darwin
import Foundation

nonisolated enum PackageKind: Equatable {
    case base, update, dlc
    /// A Switch package of a different game.
    case otherGame
}

/// Splatoon 3 title IDs share these high bits: 0100C2500FC20000 (game), …0800 (update);
/// the add-on content (Side Order) lives at 0100C2500FC21xxx.
nonisolated private let splatoonProgram: UInt64 = 0x0100_C250_0FC2_0
nonisolated private let splatoonAddOn: UInt64 = 0x0100_C250_0FC2_1

/// Reads the title ID from an NSP's ticket name (PFS0 string table) or, for an XCI, the
/// title ID in brackets that dump tools put into the file name. nil = can't tell.
nonisolated func packageKind(_ url: URL) -> PackageKind? {
    let name = url.lastPathComponent.lowercased()
    if name.hasSuffix(".xci") {
        if let tid = bracketTitleID(name) { return kind(tid) }
        return isXCI(url) ? .base : nil
    }
    guard name.hasSuffix(".nsp") || name.hasSuffix(".nsz") else { return nil }
    if let tid = ticketTitleID(url) ?? bracketTitleID(name) { return kind(tid) }
    return nil
}

nonisolated private func kind(_ tid: UInt64) -> PackageKind {
    switch tid >> 12 {
    case splatoonProgram: return tid & 0xFFF == 0x800 ? .update : .base
    case splatoonAddOn: return .dlc
    default: return .otherGame
    }
}

nonisolated private func bracketTitleID(_ name: String) -> UInt64? {
    var rest = Substring(name)
    while let open = rest.firstIndex(of: "[") {
        let after = rest[rest.index(after: open)...]
        guard let close = after.firstIndex(of: "]") else { break }
        let inner = after[..<close]
        if inner.count == 16, let tid = UInt64(inner, radix: 16) { return tid }
        rest = after[after.index(after: close)...]
    }
    return nil
}

nonisolated private func ticketTitleID(_ url: URL) -> UInt64? {
    guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? h.close() }
    guard let d = try? h.read(upToCount: 0x10000), d.count >= 0x10, d.prefix(4) == Data("PFS0".utf8) else { return nil }
    let u32 = { (o: Int) in Int(d[o]) | Int(d[o + 1]) << 8 | Int(d[o + 2]) << 16 | Int(d[o + 3]) << 24 }
    let start = 0x10 + u32(4) * 0x18, end = start + u32(8)
    guard end <= d.count else { return nil }
    let names = String(decoding: d[start..<end], as: UTF8.self).split(separator: "\0")
    guard let tik = names.first(where: { $0.hasSuffix(".tik") }) else { return nil }
    return UInt64(tik.prefix(16), radix: 16)
}

nonisolated private func isXCI(_ url: URL) -> Bool {
    guard let h = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? h.close() }
    guard (try? h.seek(toOffset: 0x100)) != nil, let magic = try? h.read(upToCount: 4) else { return false }
    return magic == Data("HEAD".utf8)
}

/// Finds the game files in `root`, `root/rom` and `root/rom/keys`. Returned paths are
/// relative to `root` when they are inside it.
struct FoundFiles {
    var base: String?
    var update: String?
    var dlc: String?
    var keys: String?
    var firmware: String?
}

func discoverGameFiles(in root: URL) -> FoundFiles {
    let fm = FileManager.default
    var found = FoundFiles()
    for sub in ["", "rom", "rom/keys", "keys"] {
        let dir = sub.isEmpty ? root : root.appending(path: sub)
        let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        for n in names {
            let rel = sub.isEmpty ? n : "\(sub)/\(n)"
            let url = dir.appending(path: n)
            let lower = n.lowercased()
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                if found.firmware == nil, lower.hasPrefix("firmware"), containsNCA(url) { found.firmware = rel }
                continue
            }
            if lower == "prod.keys" { found.keys = found.keys ?? rel; continue }
            switch packageKind(url) {
            case .base: found.base = found.base ?? rel
            case .update: found.update = found.update ?? rel
            case .dlc: found.dlc = found.dlc ?? rel
            case .otherGame, nil:
                if lower.hasSuffix(".nsp") || lower.hasSuffix(".xci") {
                    if lower.contains("upd") { found.update = found.update ?? rel }
                    else if lower.contains("dlc") || lower.contains("aoc") { found.dlc = found.dlc ?? rel }
                    else if lower.contains("base") || lower.hasSuffix(".xci") { found.base = found.base ?? rel }
                }
            }
        }
    }
    #if os(macOS)
    if found.keys == nil {
        let home = fm.homeDirectoryForCurrentUser.appending(path: ".switch/prod.keys")
        if fm.fileExists(atPath: home.path) { found.keys = home.path }
    }
    #endif
    return found
}

nonisolated func containsNCA(_ dir: URL) -> Bool {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    return names.contains { $0.lowercased().hasSuffix(".nca") }
}

/// Resolves a path saved in the settings: absolute paths stay, relative ones are inside `root`.
func resolve(_ path: String, in root: URL) -> URL {
    path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appending(path: path)
}

nonisolated func fileSize(_ url: URL) -> Int64? {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
}

func bytes(_ n: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .memory) }

func availableMemory() -> UInt64 {
    #if os(iOS)
    return UInt64(os_proc_available_memory())
    #else
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    guard r == KERN_SUCCESS else { return 0 }
    let pages = UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count) + UInt64(stats.speculative_count)
    return pages * UInt64(vm_kernel_page_size)
    #endif
}

struct NetInterface: Hashable {
    let name: String
    let ip: String
}

func networkInterfaces() -> [NetInterface] {
    var out: [NetInterface] = []
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return out }
    defer { freeifaddrs(list) }
    for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
        let flags = Int32(p.pointee.ifa_flags)
        guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET),
              flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
            out.append(NetInterface(name: String(cString: p.pointee.ifa_name), ip: String(cString: host)))
        }
    }
    return out
}

final class SystemInfo: ObservableObject {
    @Published var memory = availableMemory()
    @Published var interfaces = networkInterfaces()
    private var refresh: Task<Void, Never>?

    init() {
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.memory = availableMemory()
                self.interfaces = networkInterfaces()
            }
        }
    }

    deinit { refresh?.cancel() }
}
