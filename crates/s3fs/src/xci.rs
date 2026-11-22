//! XCI game card images.
//!
//! An XCI starts with a 0x200-byte card header (0x100 RSA signature, then the
//! "HEAD" structure). The fields used here are not encrypted:
//!   0x100 "HEAD"
//!   0x10D u8  card size code
//!   0x130 u64 offset of the root HFS0
//!   0x138 u64 size of the root HFS0 header
//! The root HFS0 holds the partitions `update`, `normal`, `secure` (and on newer
//! cards `logo`). The game's NCAs are in `secure`. They use the standard NCA
//! key-area encryption (no tickets), which Mush8's nxfs already implements.
//!
//! Some dump tools prepend the 0x1000-byte "initial data / key area"; the
//! header then sits at 0x1100. Both forms are accepted. The card's own
//! encrypted extended header (0x190..) is never read or needed.

use crate::hfs0::Hfs0;
use anyhow::{Context, Result, bail, ensure};
use nxfs::storage::{DynStorage, FileRange, Sub};
use std::fs::File;
use std::path::Path;
use std::sync::Arc;

pub struct Xci {
    /// Offset of the card header inside the file (0 or 0x1000).
    pub prefix: u64,
    pub card_size_code: u8,
    pub root: Hfs0,
}

impl Xci {
    pub fn open_file(path: &Path) -> Result<Self> {
        let f = Arc::new(File::open(path).with_context(|| format!("opening {}", path.display()))?);
        let size = f.metadata()?.len();
        Self::open(Arc::new(FileRange::new(f, 0, size)))
    }

    pub fn open(storage: DynStorage) -> Result<Self> {
        let prefix = [0u64, 0x1000]
            .into_iter()
            .find(|&p| storage.size() >= p + 0x200 && storage.read_vec(p + 0x100, 4).is_ok_and(|m| m == b"HEAD"))
            .context("not an XCI image: no HEAD magic at 0x100 or 0x1100")?;
        let h = storage.read_vec(prefix, 0x200)?;
        let card_size_code = h[0x10D];
        let root_off = u64::from_le_bytes(h[0x130..0x138].try_into()?);
        let root_hdr = u64::from_le_bytes(h[0x138..0x140].try_into()?);
        let abs = prefix + root_off;
        ensure!(root_hdr >= 0x10 && abs < storage.size(), "XCI root HFS0 at {abs:#x} is outside the image");
        let root = Hfs0::open(Arc::new(Sub::new(storage.clone(), abs, storage.size() - abs))).context("XCI root partition")?;
        Ok(Self { prefix, card_size_code, root })
    }

    pub fn partition(&self, name: &str) -> Result<Hfs0> {
        match self.root.file(name) {
            Some(s) => Hfs0::open(s).with_context(|| format!("XCI {name} partition")),
            None => bail!("XCI has no {name} partition (has: {})", self.root.entries.iter().map(|e| e.name.as_str()).collect::<Vec<_>>().join(", ")),
        }
    }

    /// The partition holding the game's NCAs.
    pub fn secure(&self) -> Result<Hfs0> {
        self.partition("secure")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hfs0::tests::build;
    use nxfs::storage::Mem;

    fn card(prefix: usize) -> Vec<u8> {
        let secure = build(&[("abc.nca", b"NCA-DATA"), ("abc.cnmt.nca", b"META")]);
        let root = build(&[("update", b""), ("normal", b""), ("secure", &secure)]);
        let mut img = vec![0u8; prefix + 0x400];
        let h = prefix;
        img[h + 0x100..h + 0x104].copy_from_slice(b"HEAD");
        img[h + 0x10D] = 0xE1;
        img[h + 0x130..h + 0x138].copy_from_slice(&0x400u64.to_le_bytes());
        img[h + 0x138..h + 0x140].copy_from_slice(&0x200u64.to_le_bytes());
        img.truncate(h + 0x400);
        img.extend_from_slice(&root);
        img
    }

    #[test]
    fn opens_plain_and_key_area_dumps() {
        for prefix in [0, 0x1000] {
            let x = Xci::open(Arc::new(Mem(card(prefix)))).unwrap();
            assert_eq!(x.prefix, prefix as u64);
            assert_eq!(x.card_size_code, 0xE1);
            let s = x.secure().unwrap();
            let names: Vec<_> = s.entries.iter().map(|e| e.name.as_str()).collect();
            assert_eq!(names, ["abc.nca", "abc.cnmt.nca"]);
            assert_eq!(s.file("abc.nca").unwrap().read_vec(0, 8).unwrap(), b"NCA-DATA");
            assert!(x.partition("logo").is_err());
        }
    }

    #[test]
    fn rejects_non_xci() {
        assert!(Xci::open(Arc::new(Mem(vec![0; 0x2000]))).is_err());
    }
}
