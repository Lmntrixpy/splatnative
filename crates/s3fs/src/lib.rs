//! SplatNative game container layer.
//!
//! Mush8's `nxfs` already handles NCA decryption, BKTR update patching, PFS0,
//! RomFS and NSO. What it lacks for Splatoon 3 is XCI support (the base game
//! here is a game card dump). This crate adds that and keeps everything else
//! delegated to `nxfs`, so there is a single implementation of each format.

pub mod hfs0;
pub mod package;
pub mod xci;

pub use package::{Container, Listing, Package};

/// Splatoon 3 program IDs.
pub const SPLATOON3_BASE: u64 = 0x0100_C250_0FC2_0000;
pub const SPLATOON3_UPDATE: u64 = 0x0100_C250_0FC2_0800;
