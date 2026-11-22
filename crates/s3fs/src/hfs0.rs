//! HFS0 ("hashed file system"), the partition format inside XCI game card images.
//!
//! Layout (all little endian):
//!   0x00 "HFS0"  0x04 u32 file count  0x08 u32 string table size  0x0C u32 reserved
//!   0x10 file entries, 0x40 bytes each:
//!        0x00 u64 data offset (relative to end of header)
//!        0x08 u64 size
//!        0x10 u32 name offset into string table
//!        0x14 u32 hashed region size
//!        0x18 u64 reserved
//!        0x20 [u8; 32] SHA-256 of the first `hashed region size` bytes
//!   string table, then file data.
//!
//! HFS0 is not encrypted, so this parser works without any keys.

use anyhow::{Result, bail, ensure};
use nxfs::storage::{DynStorage, Sub};
use std::sync::Arc;

const ENTRY: usize = 0x40;

#[derive(Debug, Clone)]
pub struct Entry {
    pub name: String,
    /// Absolute offset inside the HFS0's storage.
    pub offset: u64,
    pub size: u64,
    pub hashed_size: u32,
    pub hash: [u8; 32],
}

pub struct Hfs0 {
    storage: DynStorage,
    pub entries: Vec<Entry>,
}

impl Hfs0 {
    pub fn open(storage: DynStorage) -> Result<Self> {
        let hdr = storage.read_vec(0, 16)?;
        if &hdr[..4] != b"HFS0" {
            bail!("not an HFS0 partition (magic {:02x?})", &hdr[..4]);
        }
        let n = u32::from_le_bytes(hdr[4..8].try_into()?) as usize;
        let st = u32::from_le_bytes(hdr[8..12].try_into()?) as usize;
        ensure!(n <= 0x10000 && st <= 0x10_0000, "implausible HFS0 header: {n} files, {st:#x} bytes of names");
        let table = storage.read_vec(16, n * ENTRY + st)?;
        let strs = &table[n * ENTRY..];
        let data = (16 + n * ENTRY + st) as u64;
        let total = storage.size();
        let mut entries = Vec::with_capacity(n);
        for i in 0..n {
            let e = &table[i * ENTRY..(i + 1) * ENTRY];
            let off = u64::from_le_bytes(e[0..8].try_into()?);
            let size = u64::from_le_bytes(e[8..16].try_into()?);
            let so = u32::from_le_bytes(e[16..20].try_into()?) as usize;
            let hashed_size = u32::from_le_bytes(e[20..24].try_into()?);
            ensure!(so < strs.len().max(1), "HFS0 entry {i}: name offset {so:#x} outside the string table");
            let end = strs[so..].iter().position(|&c| c == 0).unwrap_or(strs.len() - so);
            let name = String::from_utf8_lossy(&strs[so..so + end]).into_owned();
            let offset = data + off;
            ensure!(offset.checked_add(size).is_some_and(|e| e <= total), "HFS0 entry {name}: {offset:#x}+{size:#x} is past the end ({total:#x})");
            entries.push(Entry { name, offset, size, hashed_size, hash: e[0x20..0x40].try_into()? });
        }
        Ok(Self { storage, entries })
    }

    pub fn entry(&self, name: &str) -> Option<&Entry> {
        self.entries.iter().find(|e| e.name == name)
    }

    pub fn file(&self, name: &str) -> Option<DynStorage> {
        self.entry(name).map(|e| self.storage_of(e))
    }

    pub fn storage_of(&self, e: &Entry) -> DynStorage {
        Arc::new(Sub::new(self.storage.clone(), e.offset, e.size))
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use nxfs::storage::Mem;

    /// Builds an HFS0 image with the given files.
    pub(crate) fn build(files: &[(&str, &[u8])]) -> Vec<u8> {
        let mut names = Vec::new();
        let mut name_offs = Vec::new();
        for (n, _) in files {
            name_offs.push(names.len() as u32);
            names.extend_from_slice(n.as_bytes());
            names.push(0);
        }
        while names.len() % 0x10 != 0 {
            names.push(0);
        }
        let mut out = Vec::new();
        out.extend_from_slice(b"HFS0");
        out.extend_from_slice(&(files.len() as u32).to_le_bytes());
        out.extend_from_slice(&(names.len() as u32).to_le_bytes());
        out.extend_from_slice(&0u32.to_le_bytes());
        let mut off = 0u64;
        for (i, (_, d)) in files.iter().enumerate() {
            out.extend_from_slice(&off.to_le_bytes());
            out.extend_from_slice(&(d.len() as u64).to_le_bytes());
            out.extend_from_slice(&name_offs[i].to_le_bytes());
            out.extend_from_slice(&0x200u32.to_le_bytes());
            out.extend_from_slice(&0u64.to_le_bytes());
            out.extend_from_slice(&[i as u8; 32]);
            off += d.len() as u64;
        }
        out.extend_from_slice(&names);
        for (_, d) in files {
            out.extend_from_slice(d);
        }
        out
    }

    #[test]
    fn parses_entries_and_data() {
        let img = build(&[("update", b"aaaa"), ("secure", b"bbbbbbbb")]);
        let h = Hfs0::open(Arc::new(Mem(img))).unwrap();
        assert_eq!(h.entries.len(), 2);
        assert_eq!(h.entries[1].name, "secure");
        assert_eq!(h.entries[1].hash, [1; 32]);
        assert_eq!(h.file("secure").unwrap().read_vec(0, 8).unwrap(), b"bbbbbbbb");
        assert_eq!(h.file("update").unwrap().read_vec(0, 4).unwrap(), b"aaaa");
        assert!(h.file("normal").is_none());
    }

    #[test]
    fn rejects_bad_magic_and_truncation() {
        assert!(Hfs0::open(Arc::new(Mem(b"PFS0\0\0\0\0\0\0\0\0\0\0\0\0".to_vec()))).is_err());
        let mut img = build(&[("secure", b"bbbbbbbb")]);
        img.truncate(img.len() - 4);
        assert!(Hfs0::open(Arc::new(Mem(img))).is_err());
    }
}
