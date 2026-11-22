//! Requirement analysis of an extracted ExeFS.
//!
//! Everything reported here is measured from the game binary and from the
//! Mush8 / Prelude source trees on disk. Nothing is assumed:
//!   - modules and build IDs come from the NSO headers,
//!   - unresolved imports are dynamic symbols no module defines (those must
//!     be provided by the host, like Mush8's `nvnBootstrapLoader`),
//!   - NVN procs and service names are string literals in the modules'
//!     read-only data (NVN procs are looked up by name at runtime, services
//!     are opened by their 8-byte name through `sm:`),
//!   - "implemented by Mush8" is read from Mush8's source.

use anyhow::{Context, Result, ensure};
use nxfs::nso::Nso;
use std::collections::{BTreeMap, BTreeSet};
use std::path::Path;

/// Horizon service names, from the public Switchbrew service list. Used only to
/// recognize string literals as service names; presence in the game is measured.
const KNOWN_SERVICES: &[&str] = &[
    "acc:u0", "acc:u1", "aoc:u", "apm", "apm:p", "appletAE", "appletOE", "audin:u", "audout:u", "audrec:u", "audren:u",
    "bcat:a", "bcat:m", "bcat:s", "bcat:u", "bsd:a", "bsd:s", "bsd:u", "caps:a", "caps:c", "caps:sc", "caps:ss", "caps:su", "caps:u",
    "csrng", "ectx:aw", "ectx:r", "ectx:w", "erpt:c", "erpt:r", "fatal:u", "friend:a", "friend:m", "friend:s", "friend:u",
    "friend:v", "fsp-srv", "grc:c", "grc:d", "hid", "hid:dbg", "hid:sys", "hidbus", "hwopus", "irs", "ldn:u", "lm", "lp2p:app",
    "mii:e", "mii:u", "mm:u", "nfc:user", "nfp:user", "nifm:a", "nifm:s", "nifm:u", "nim:eca", "notif:a", "ns:am2", "ns:ec",
    "ns:su", "nsd:a", "nsd:u", "ntc", "nvdrv", "nvdrv:a", "olsc:u", "ovln:rcv", "ovln:snd", "pctl", "pctl:a", "pctl:r", "pctl:s",
    "pdm:qry", "pl:s", "pl:u", "prepo:a", "prepo:a2", "prepo:m", "prepo:s", "prepo:u", "psm", "set", "set:sys", "sfdnsres",
    "ssl", "time:a", "time:s", "time:u", "vi:m", "vi:s", "vi:u", "ro:1", "ldr:ro", "arp:r", "spl:", "es", "ngct:u", "hshl:sys",
];

struct Module {
    name: String,
    nso: Nso,
    syms: Vec<nxfs::nso::Symbol>,
}

pub fn run(exefs: &Path, mush8: &Path, prelude: &Path) -> Result<()> {
    let mut names: Vec<String> = std::fs::read_dir(exefs)
        .with_context(|| exefs.display().to_string())?
        .filter_map(|e| e.ok()?.file_name().into_string().ok())
        .filter(|n| !n.ends_with(".npdm") && !n.starts_with('.'))
        .collect();
    names.sort_by_key(|n| load_order(n));
    let mut mods = Vec::new();
    for n in &names {
        let bytes = std::fs::read(exefs.join(n))?;
        if !bytes.starts_with(b"NSO0") {
            continue;
        }
        let nso = Nso::parse(&bytes).with_context(|| n.clone())?;
        let syms = nso.symbols();
        mods.push(Module { name: n.clone(), nso, syms });
    }
    ensure!(!mods.is_empty(), "no NSO modules in {}", exefs.display());

    println!("# Modules (load order)");
    for m in &mods {
        let n = &m.nso;
        println!(
            "{:<10} build {}  text {:#x}  ro {:#x}  data {:#x}  bss {:#x}  symbols {}",
            m.name,
            hex::encode_upper(&n.module_id[..20]),
            n.text.size,
            n.ro.size,
            n.data.size,
            n.bss_size,
            m.syms.len()
        );
    }
    let mush8_modules = ["main", "subsdk0", "sdk"];
    let extra: Vec<_> = mods.iter().map(|m| m.name.as_str()).filter(|n| !mush8_modules.contains(n) && *n != "rtld").collect();
    if !extra.is_empty() {
        println!("NOTE: Mush8 hardcodes the module list {mush8_modules:?}; this game also has {extra:?}");
    }
    if mods.iter().any(|m| m.name == "rtld") {
        println!("NOTE: rtld is present; Mush8 replaces it with its own loader (it never runs rtld)");
    }

    if let Ok(npdm) = std::fs::read(exefs.join("main.npdm")) {
        if npdm.len() >= 0x20 && &npdm[..4] == b"META" {
            println!(
                "\n# NPDM\nflags {:#x} (64-bit: {})  main thread priority {}  core {}  stack {:#x}",
                npdm[0xC],
                npdm[0xC] & 1 != 0,
                npdm[0xE],
                npdm[0xF],
                u32::from_le_bytes(npdm[0x1C..0x20].try_into()?)
            );
        }
    }

    let defined: BTreeSet<&str> = mods.iter().flat_map(|m| m.syms.iter().filter(|s| s.defined).map(|s| s.name.as_str())).collect();
    let mut unresolved: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for m in &mods {
        for s in m.syms.iter().filter(|s| !s.defined && !defined.contains(s.name.as_str())) {
            unresolved.entry(&s.name).or_default().push(&m.name);
        }
    }
    let hle = mush8_hle(mush8);
    println!("\n# Imports no module defines ({})", unresolved.len());
    for (name, by) in &unresolved {
        let tag = if hle.contains(*name) { "mush8-hle" } else { "MISSING " };
        println!("{tag}  {}  <- {}", nxfs::nso::demangle(name), by.join(","));
    }

    let strings: BTreeSet<String> = mods.iter().flat_map(|m| ro_strings(&m.nso)).collect();

    let nvn_used: BTreeSet<&str> = strings.iter().filter(|s| is_nvn_proc(s)).map(String::as_str).collect();
    let nvn_impl = mush8_nvn(mush8);
    let missing_nvn: Vec<_> = nvn_used.iter().filter(|p| !nvn_impl.contains(**p)).collect();
    println!(
        "\n# NVN procs named in the game: {}  (Mush8 implements {} of them, {} not implemented)",
        nvn_used.len(),
        nvn_used.len() - missing_nvn.len(),
        missing_nvn.len()
    );
    for p in &missing_nvn {
        println!("  not in Mush8: {p}");
    }

    let svc_impl = mush8_services(mush8);
    println!("\n# Horizon services named in the game");
    for s in KNOWN_SERVICES.iter().filter(|s| strings.contains(**s)) {
        println!("  {:<10} {}", s, if svc_impl.contains(*s) { "mush8" } else { "stub/missing in mush8" });
    }

    println!("\n# Nextendo (Prelude) NPLN patches for main");
    let main = mods.iter().find(|m| m.name == "main").context("no main module")?;
    let build = hex::encode_upper(&main.nso.module_id[..20]);
    let dir = prelude.join("romfs/sd/atmosphere/exefs_patches");
    let mut found = false;
    for set in ["s3certbypass", "s3peername"] {
        let p = dir.join(set).join(format!("{build}.ips"));
        match std::fs::read(&p) {
            Ok(ips) => {
                found = true;
                println!("  {set}: {}", p.display());
                for (off, data) in ips32_records(&ips)? {
                    let at = off.checked_sub(0x100).context("IPS offset below the NSO header")? as usize;
                    let cur = main.nso.image.get(at..at + data.len()).map(hex::encode_upper).unwrap_or_else(|| "out of range".into());
                    println!("    text+{at:#x}: {cur} -> {}", hex::encode_upper(&data));
                }
            }
            Err(_) => println!("  {set}: none for build {build}"),
        }
    }
    if !found {
        println!("  this game version has no Nextendo patch yet: online would need new patches");
    }
    Ok(())
}

fn load_order(name: &str) -> (u32, u32) {
    match name {
        "rtld" => (0, 0),
        "main" => (1, 0),
        "sdk" => (3, 0),
        n => match n.strip_prefix("subsdk").and_then(|i| i.parse().ok()) {
            Some(i) => (2, i),
            None => (4, 0),
        },
    }
}

fn ro_strings(n: &Nso) -> Vec<String> {
    let ro = &n.image[n.ro.mem_offset as usize..][..n.ro.size as usize];
    let mut out = Vec::new();
    for chunk in ro.split(|&b| b == 0) {
        if chunk.len() >= 2 && chunk.len() <= 128 && chunk.iter().all(|c| c.is_ascii_graphic()) {
            out.push(String::from_utf8_lossy(chunk).into_owned());
        }
    }
    out
}

fn is_nvn_proc(s: &str) -> bool {
    s.len() > 4 && s.starts_with("nvn") && s.as_bytes()[3].is_ascii_uppercase() && s.bytes().all(|c| c.is_ascii_alphanumeric())
}

fn rust_sources(dir: &Path) -> Vec<String> {
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(dir) else { return out };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            out.extend(rust_sources(&p));
        } else if p.extension().is_some_and(|x| x == "rs") {
            if let Ok(t) = std::fs::read_to_string(&p) {
                out.push(t);
            }
        }
    }
    out
}

fn quoted(text: &str) -> impl Iterator<Item = &str> {
    text.split('"').skip(1).step_by(2)
}

fn mush8_nvn(mush8: &Path) -> BTreeSet<String> {
    rust_sources(&mush8.join("crates/nxhost/src/nvn")).iter().flat_map(|t| quoted(t).filter(|s| is_nvn_proc(s)).map(String::from).collect::<Vec<_>>()).collect()
}

fn mush8_hle(mush8: &Path) -> BTreeSet<String> {
    let mut s: BTreeSet<String> = BTreeSet::new();
    for t in rust_sources(&mush8.join("crates/nxhost/src")) {
        s.extend(quoted(&t).filter(|q| q.starts_with("_Z") || q.starts_with("nvn")).map(String::from));
    }
    s
}

fn mush8_services(mush8: &Path) -> BTreeSet<String> {
    let Ok(t) = std::fs::read_to_string(mush8.join("crates/nxhost/src/services/mod.rs")) else { return BTreeSet::new() };
    t.lines().filter(|l| l.contains("=>")).flat_map(|l| quoted(l.split("=>").next().unwrap_or("")).map(String::from).collect::<Vec<_>>()).collect()
}

/// IPS32: "IPS32", records of u32 BE offset, u16 BE size, data; "EEOF".
fn ips32_records(b: &[u8]) -> Result<Vec<(u64, Vec<u8>)>> {
    ensure!(b.starts_with(b"IPS32"), "not an IPS32 patch");
    let mut i = 5;
    let mut out = Vec::new();
    while i + 4 <= b.len() && &b[i..i + 4] != b"EEOF" {
        ensure!(i + 6 <= b.len(), "truncated IPS32 record");
        let off = u32::from_be_bytes(b[i..i + 4].try_into()?) as u64;
        let len = u16::from_be_bytes(b[i + 4..i + 6].try_into()?) as usize;
        ensure!(len != 0, "IPS32 RLE records are not used by these patches");
        ensure!(i + 6 + len <= b.len(), "truncated IPS32 data");
        out.push((off, b[i + 6..i + 6 + len].to_vec()));
        i += 6 + len;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_prelude_s3peername_patch() {
        // s3peername/28C4287AEE36F7499DA60F3E68B54C70DA382D75.ips from Prelude-Nextendo c406284
        let ips = hex::decode("49505333320014e1b000041f2003d50014dd800004f4031f2a45454f46").unwrap();
        let r = ips32_records(&ips).unwrap();
        assert_eq!(r, vec![(0x14e1b0, vec![0x1f, 0x20, 0x03, 0xd5]), (0x14dd80, vec![0xf4, 0x03, 0x1f, 0x2a])]);
    }

    #[test]
    fn nvn_proc_names() {
        assert!(is_nvn_proc("nvnDeviceInitialize"));
        assert!(!is_nvn_proc("nvn"));
        assert!(!is_nvn_proc("nvnfoo"));
        assert!(!is_nvn_proc("nvnDevice Initialize"));
    }

    #[test]
    fn module_order() {
        let mut v = vec!["sdk", "subsdk10", "main", "subsdk2", "rtld"];
        v.sort_by_key(|n| load_order(n));
        assert_eq!(v, ["rtld", "main", "subsdk2", "subsdk10", "sdk"]);
    }
}
