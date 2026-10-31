//! Native mod builder: apply `.hnmod` bundles from native-mods/ and build the game.
//!
//! Usage: cargo run -p xtask -- build-native
//!
//! This is the Rust equivalent of Fabric's mod system: you drop `.hnmod` files
//! (source-only bundles of Rust + mixins) into native-mods/, and this builder
//! applies them to the game source and compiles a native Horizon build that
//! includes them.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn run() -> Result<(), String> {
    // horizon-mixins doesn't allow symlinks (CLAUDE.md is a symlink to AGENTS.md)
    let _ = std::fs::remove_file("CLAUDE.md");
    let native_mods_dir = PathBuf::from("native-mods");
    if !native_mods_dir.is_dir() {
        fs::create_dir_all(&native_mods_dir).map_err(|e| e.to_string())?;
        println!("Created native-mods/ directory.");
        println!("Drop .hnmod files there and re-run this command.");
        return Ok(());
    }

    // Find all .hnmod files
    let mut hnmods: Vec<PathBuf> = fs::read_dir(&native_mods_dir)
        .map_err(|e| e.to_string())?
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.extension().map(|e| e == "hnmod").unwrap_or(false))
        .collect();
    hnmods.sort();

    if hnmods.is_empty() {
        println!("No .hnmod files found in native-mods/. Nothing to build.");
        return Ok(());
    }

    println!("Found {} native mod(s):", hnmods.len());
    for p in &hnmods {
        println!("  - {}", p.display());
    }

    // Create output workspace for applied mods
    let _workspace = Path::new(".");
    let staging_dir = PathBuf::from("target/native-mod-stage");
    let _ = fs::remove_dir_all(&staging_dir);
    fs::create_dir_all(&staging_dir).map_err(|e| e.to_string())?;

    // Build horizon-mixins if available, or check tools/
    let horizon_mixins = PathBuf::from("tools/horizon-mixins/target/debug/horizon-mixins");
    if !horizon_mixins.exists() {
        println!("Building horizon-mixins (first time)...");
        let status = Command::new("cargo")
            .args(["build", "--locked", "-p", "horizon-mixins-cli"])
            .current_dir("tools/horizon-mixins")
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err("Failed to build horizon-mixins".into());
        }
    }

    // Unpack each .hnmod and merge into a staging directory
    for hnmod in &hnmods {
        println!("Extracting {}...", hnmod.display());
        let extract_dir = staging_dir.join(hnmod.file_stem().unwrap_or_default());
        fs::create_dir_all(&extract_dir).map_err(|e| e.to_string())?;

        // Unzip
        let status = Command::new("unzip")
            .arg("-o")
            .arg(hnmod)
            .arg("-d")
            .arg(&extract_dir)
            .status()
            .map_err(|e| e.to_string())?;
        if !status.success() {
            return Err(format!("Failed to extract {}", hnmod.display()));
        }
    }

    // Collect all bundle directories (each .hnmod extracts to mixins/<id>/ under its own dir)
    let mut mods_dirs: Vec<PathBuf> = Vec::new();
    for hnmod in &hnmods {
        let name = hnmod
            .file_stem()
            .unwrap_or_default()
            .to_str()
            .unwrap_or("");
        let bundles_dir = staging_dir.join(name).join("mixins");
        if !bundles_dir.exists() {
            return Err(format!("No mixins/ folder found in {}", hnmod.display()));
        }
        // Find the bundle dir (mixins/<id>/)
        for entry in fs::read_dir(&bundles_dir).map_err(|e| e.to_string())?.flatten() {
            if entry.path().join("horizon-mixin.toml").is_file() {
                mods_dirs.push(entry.path());
            }
        }
    }

    if mods_dirs.is_empty() {
        return Err("No mod bundles found in any .hnmod files".into());
    }

    // Apply each mod bundle
    // Collect them into one mods dir, then apply all at once
    let merged_mods = staging_dir.join("merged_mods");
    fs::create_dir_all(&merged_mods).map_err(|e| e.to_string())?;
    for d in &mods_dirs {
        let name = d.file_name().unwrap_or_default();
        let target = merged_mods.join(name);
        fs::create_dir_all(&target).map_err(|e| e.to_string())?;
        for entry in fs::read_dir(d).map_err(|e| e.to_string())?.flatten() {
            fs::copy(entry.path(), target.join(entry.file_name()))
                .map_err(|e| e.to_string())?;
        }
    }

    // Remove symlinks (horizon-mixins doesn't support them)
    let _ = walk_remove_symlinks(&merged_mods);

    // Apply with horizon-mixins
    let out_dir = PathBuf::from("/home/binwalk").join("horizon-build-output");
    let _ = fs::remove_dir_all(&out_dir);

    println!("Applying {} mod bundle(s)...", mods_dirs.len());
    let status = Command::new(&horizon_mixins)
        .arg("apply")
        .arg("--workspace")
        .arg(".")
        .arg("--mods")
        .arg(&merged_mods)
        .arg("--out")
        .arg(&out_dir)
        .status()
        .map_err(|e| e.to_string())?;

    if !status.success() {
        return Err("horizon-mixins apply failed".into());
    }

    // Build
    println!("Building Horizon with native mods...");
    let status = Command::new("cargo")
        .arg("build")
        .arg("--release")
        .args(["-p", "horizon-client", "--bin", "horizon-client"])
        .current_dir(&out_dir)
        .status()
        .map_err(|e| e.to_string())?;

    if !status.success() {
        return Err("cargo build failed".into());
    }

    let binary = out_dir.join("target/release/horizon-client");
    println!();
    println!("Build complete! Binary: {}", binary.display());
    println!("Run it with: {} --resources ...", binary.display());
    Ok(())
}

fn walk_remove_symlinks(path: &Path) {
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_symlink() {
                let _ = fs::remove_file(&p);
            } else if p.is_dir() {
                walk_remove_symlinks(&p);
            }
        }
    }
}
