//! Keyless listing of a game package (NSP or XCI), via `nxfs::package_files`.

use anyhow::Result;
use nxfs::storage::DynStorage;
use std::path::Path;

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
        let mut magic = [0u8; 4];
        std::io::Read::read_exact(&mut std::fs::File::open(path)?, &mut magic)?;
        let container = if &magic == b"PFS0" { Container::Nsp } else { Container::Xci };
        let files = nxfs::package_files(path)?;
        let entries = files.iter().map(|(n, s)| RawEntry { name: n.clone(), size: s.size() }).collect();
        let storages = files.into_iter().map(|(_, s)| s).collect();
        Ok(Self { container, entries, storages })
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
