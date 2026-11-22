//! A game package: the NCAs of one base game or update, whatever container
//! (NSP or XCI) they came in. This is the XCI-capable counterpart of
//! `nxfs::Nsp`, which only understands NSP (PFS0) files.

use crate::xci::Xci;
use anyhow::{Context, Result, bail};
use nxfs::keys::Keys;
use nxfs::nca::{ContentType, Nca, TitleKeys};
use nxfs::pfs0::Pfs0;
use nxfs::storage::{DynStorage, FileRange};
use std::fs::File;
use std::path::Path;
use std::sync::Arc;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Container {
    Nsp,
    Xci,
}

/// A file inside the container, before any decryption.
#[derive(Debug, Clone)]
pub struct RawEntry {
    pub name: String,
    pub size: u64,
}

pub struct Listing {
    pub container: Container,
    pub entries: Vec<RawEntry>,
    storages: Vec<DynStorage>,
}

impl Listing {
    /// Lists the container's files. Needs no keys.
    pub fn open(path: &Path) -> Result<Self> {
        let f = Arc::new(File::open(path).with_context(|| format!("opening {}", path.display()))?);
        let size = f.metadata()?.len();
        let whole: DynStorage = Arc::new(FileRange::new(f, 0, size));
        let magic = whole.read_vec(0, 4)?;
        if magic == b"PFS0" {
            let pfs = Pfs0::open(whole)?;
            let storages = pfs.entries.iter().map(|e| pfs.storage_of(e)).collect();
            let entries = pfs.entries.iter().map(|e| RawEntry { name: e.name.clone(), size: e.size }).collect();
            return Ok(Self { container: Container::Nsp, entries, storages });
        }
        let xci = Xci::open(whole).with_context(|| format!("{} is neither an NSP nor an XCI", path.display()))?;
        let secure = xci.secure()?;
        let storages = secure.entries.iter().map(|e| secure.storage_of(e)).collect();
        let entries = secure.entries.iter().map(|e| RawEntry { name: e.name.clone(), size: e.size }).collect();
        Ok(Self { container: Container::Xci, entries, storages })
    }

    pub fn storage(&self, name: &str) -> Option<DynStorage> {
        self.entries.iter().position(|e| e.name == name).map(|i| self.storages[i].clone())
    }

    /// The plaintext CNMT XML some NSP dumps carry, if present.
    pub fn cnmt_xml(&self) -> Option<String> {
        let e = self.entries.iter().find(|e| e.name.ends_with(".cnmt.xml"))?;
        let s = self.storage(&e.name)?;
        String::from_utf8(s.read_vec(0, e.size as usize).ok()?).ok()
    }
}

pub struct Package {
    pub container: Container,
    pub ncas: Vec<Nca>,
}

impl Package {
    /// Opens and decrypts the NCA headers. Needs the user's own `prod.keys`.
    pub fn open(path: &Path, keys: &Keys) -> Result<Self> {
        let l = Listing::open(path)?;
        let mut title_keys = TitleKeys::new();
        for e in l.entries.iter().filter(|e| e.name.ends_with(".tik")) {
            let tik = l.storage(&e.name).unwrap().read_vec(0, e.size as usize)?;
            let (rights, key) = nxfs::nca::ticket_title_key(keys, &tik).with_context(|| e.name.clone())?;
            title_keys.insert(rights, key);
        }
        let mut ncas = Vec::new();
        for e in l.entries.iter().filter(|e| e.name.ends_with(".nca") || e.name.ends_with(".ncz")) {
            if e.name.ends_with(".ncz") {
                bail!("{}: compressed NCZ content is not supported, use an uncompressed dump", e.name);
            }
            ncas.push(Nca::open(&e.name, l.storage(&e.name).unwrap(), keys, &title_keys)?);
        }
        Ok(Self { container: l.container, ncas })
    }

    pub fn find(&self, t: ContentType) -> Option<&Nca> {
        self.ncas.iter().find(|n| n.content_type == t)
    }

    pub fn program(&self) -> Result<&Nca> {
        self.find(ContentType::Program).context("no Program NCA")
    }
}
