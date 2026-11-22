//! s3tool: host-side tooling for SplatNative.
//!
//!   info     list a dump's contents (no keys needed)
//!   inspect  decrypt NCA headers and show versions, ExeFS modules and build IDs
//!   extract  write ExeFS, control data and optionally the update-patched RomFS
//!   analyze  measure an extracted ExeFS against Mush8: imports, NVN procs, services,
//!            Nextendo patch availability
//!
//! Keys are the user's own `prod.keys` dumped from their console. Nothing here
//! obtains keys or bypasses anything; without keys only `info` works.

mod analyze;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use nxfs::keys::Keys;
use nxfs::nca::{ContentType, FsType, Nca};
use nxfs::pfs0::Pfs0;
use nxfs::romfs::RomFs;
use nxfs::storage::Storage;
use s3fs::{Listing, Package};
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Parser)]
#[command(about = "SplatNative: Splatoon 3 dump inspection and runtime requirement analysis")]
struct Cli {
    /// The user's own prod.keys (default: ~/.switch/prod.keys)
    #[arg(long, global = true)]
    keys: Option<PathBuf>,
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    Info { files: Vec<PathBuf> },
    Inspect { files: Vec<PathBuf> },
    Extract {
        #[arg(long)]
        base: PathBuf,
        #[arg(long)]
        update: Option<PathBuf>,
        #[arg(long)]
        out: PathBuf,
        #[arg(long)]
        romfs: bool,
    },
    Analyze {
        /// Directory with main, subsdk*, sdk, main.npdm
        exefs: PathBuf,
        /// Mush8 checkout, to compare against what it implements
        #[arg(long, default_value = "third_party/mush8")]
        mush8: PathBuf,
        /// Prelude-Nextendo checkout, for the Splatoon 3 NPLN patches
        #[arg(long, default_value = "third_party/Prelude-Nextendo")]
        prelude: PathBuf,
    },
}

fn keys(path: &Option<PathBuf>) -> Result<Keys> {
    let p = match path {
        Some(p) => p.clone(),
        None => PathBuf::from(std::env::var("HOME").unwrap_or_default()).join(".switch/prod.keys"),
    };
    Keys::load(&p).with_context(|| format!("no keys at {}: pass --keys with the prod.keys dumped from your own console", p.display()))
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match &cli.cmd {
        Cmd::Info { files } => {
            for f in files {
                let l = Listing::open(f)?;
                println!("== {} ({:?})", f.display(), l.container);
                for e in &l.entries {
                    println!("  {:>14}  {}", e.size, e.name);
                }
                if let Some(x) = l.cnmt_xml() {
                    for tag in ["Type", "Id", "Version", "RequiredSystemVersion", "KeyGenerationMin"] {
                        if let Some(v) = xml_tag(&x, tag) {
                            println!("  cnmt {tag}: {v}");
                        }
                    }
                }
            }
        }
        Cmd::Inspect { files } => {
            let k = keys(&cli.keys)?;
            for f in files {
                let p = Package::open(f, &k)?;
                println!("== {} ({:?})", f.display(), Listing::open(f)?.container);
                for n in &p.ncas {
                    println!("  {} {:?} program={:016x} keygen={}", n.name, n.content_type, n.program_id, n.key_generation);
                }
                if let Some(c) = p.find(ContentType::Control) {
                    if let Ok(v) = display_version(c) {
                        println!("  display version: {v}");
                    }
                }
                if let Ok(prog) = program(&p) {
                    if let Ok(pfs) = exefs(prog) {
                        for e in &pfs.entries {
                            let s = pfs.storage_of(e);
                            let head = s.read_vec(0, 0x60.min(e.size as usize))?;
                            let id = if head.starts_with(b"NSO0") { hex::encode_upper(&head[0x40..0x54]) } else { String::new() };
                            println!("  exefs/{:<10} {:>10}  {id}", e.name, e.size);
                        }
                    }
                }
            }
        }
        Cmd::Extract { base, update, out, romfs } => {
            let k = keys(&cli.keys)?;
            let base = Package::open(base, &k)?;
            let update = update.as_ref().map(|u| Package::open(u, &k)).transpose()?;
            let latest = update.as_ref().unwrap_or(&base);
            if let Some(c) = latest.find(ContentType::Control) {
                let fs = RomFs::open(c.fs_storage(section(c, FsType::RomFs)?)?)?;
                for f in fs.files() {
                    write_file(fs.storage().as_ref(), f.offset, f.size, &out.join("control").join(&f.path[1..]))?;
                }
                println!("display version: {}", display_version(c).unwrap_or_else(|e| format!("? ({e:#})")));
            }
            let pfs = exefs(program(latest)?)?;
            for e in &pfs.entries {
                write_file(pfs.storage_of(e).as_ref(), 0, e.size, &out.join("exefs").join(&e.name))?;
                println!("exefs/{} ({} bytes)", e.name, e.size);
            }
            if *romfs {
                let storage = match &update {
                    Some(u) => program(u)?.patched_romfs(program(&base)?)?,
                    None => program(&base)?.fs_storage(section(program(&base)?, FsType::RomFs)?)?,
                };
                let fs = RomFs::open(storage)?;
                let files = fs.files();
                let total: u64 = files.iter().map(|f| f.size).sum();
                println!("romfs: {} files, {:.2} GB", files.len(), total as f64 / 1e9);
                for (i, f) in files.iter().enumerate() {
                    write_file(fs.storage().as_ref(), f.offset, f.size, &out.join("romfs").join(&f.path[1..]))?;
                    if i % 1000 == 0 {
                        eprintln!("  [{i}/{}] {}", files.len(), f.path);
                    }
                }
            }
        }
        Cmd::Analyze { exefs, mush8, prelude } => analyze::run(exefs, mush8, prelude)?,
    }
    Ok(())
}

fn section(n: &Nca, t: FsType) -> Result<&nxfs::nca::Section> {
    n.sections.iter().find(|s| s.fs_type == t).with_context(|| format!("{}: no {t:?} section", n.name))
}

fn program(p: &Package) -> Result<&Nca> {
    p.find(ContentType::Program).context("no Program NCA")
}

fn exefs(prog: &Nca) -> Result<Pfs0> {
    Pfs0::open(prog.fs_storage(section(prog, FsType::PartitionFs)?)?)
}

fn display_version(control: &Nca) -> Result<String> {
    let fs = RomFs::open(control.fs_storage(section(control, FsType::RomFs)?)?)?;
    let f = fs.files().into_iter().find(|f| f.path == "/control.nacp").context("no control.nacp")?;
    let v = fs.storage().read_vec(f.offset + 0x3060, 0x10)?;
    Ok(String::from_utf8_lossy(&v[..v.iter().position(|&c| c == 0).unwrap_or(16)]).into_owned())
}

fn write_file(s: &dyn Storage, offset: u64, size: u64, path: &Path) -> Result<()> {
    if let Some(d) = path.parent() {
        std::fs::create_dir_all(d)?;
    }
    let mut f = std::io::BufWriter::new(std::fs::File::create(path).with_context(|| path.display().to_string())?);
    let mut pos = 0u64;
    while pos < size {
        let n = (size - pos).min(8 << 20) as usize;
        f.write_all(&s.read_vec(offset + pos, n)?)?;
        pos += n as u64;
    }
    Ok(())
}

fn xml_tag<'a>(x: &'a str, tag: &str) -> Option<&'a str> {
    let open = format!("<{tag}>");
    let start = x.find(&open)? + open.len();
    let end = x[start..].find(&format!("</{tag}>"))?;
    Some(&x[start..start + end])
}
