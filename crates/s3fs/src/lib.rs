//! SplatNative game container layer.
//!
//! All container formats live in Mush8's `nxfs` (XCI/HFS0 were added there by
//! patches/mush8/0004). This crate only adds what the host tools need on top:
//! a keyless listing and Splatoon 3 constants.

pub mod package;

pub use nxfs::Nsp as Package;
pub use package::{Container, Listing};

/// Splatoon 3 program IDs.
pub const SPLATOON3_BASE: u64 = 0x0100_C250_0FC2_0000;
pub const SPLATOON3_UPDATE: u64 = 0x0100_C250_0FC2_0800;
