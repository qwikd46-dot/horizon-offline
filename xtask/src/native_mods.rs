//! Native mod builder: apply `.hnmod` bundles from native-mods/ and build the game.
//!
//! Usage: cargo run -p xtask -- build-native
//!
//! This is the Rust equivalent of Fabric's mod system: you drop `.hnmod` files
//! (source-only bundles of Rust + mixins) into native-mods/, and this builder
//! applies them to the game source and compiles a native Horizon build that
//! includes them.

use std::collections::BTreeMap;
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The biggest `.hnmod` this reads and the most its files may expand to, as the
/// launcher's own bundle reader (`horizon_mods::index::native::Bundle::read`).
const MAX_FILE: u64 = 64 * 1024 * 1024;

pub fn run() -> Result<(), String> {
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
    let staging_dir = PathBuf::from("target/native-mod-stage");
    let _ = fs::remove_dir_all(&staging_dir);
    fs::create_dir_all(&staging_dir).map_err(|e| e.to_string())?;

    // Build horizon-mixins if available, or check tools/
    let horizon_mixins = PathBuf::from("tools/horizon-mixins/target/debug/horizon-mixins");
    if !horizon_mixins.exists() {
        if !Path::new("tools/horizon-mixins").is_dir() {
            return Err(
                "tools/horizon-mixins is missing: clone https://github.com/horizon-rust/horizon-mixins there first."
                    .into(),
            );
        }
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

    // Unpack each .hnmod into the staging directory, validating every path so a
    // crafted bundle cannot escape it (no `..`, absolute paths, drive letters,
    // backslashes or symlinks), as the launcher's bundle reader does.
    let mut bundle_dirs: Vec<PathBuf> = Vec::new();
    for hnmod in &hnmods {
        println!("Extracting {}...", hnmod.display());
        let stem = hnmod.file_stem().unwrap_or_default().to_str().unwrap_or("");
        let extract_dir = staging_dir.join(stem);
        fs::create_dir_all(&extract_dir).map_err(|e| e.to_string())?;
        let files = read_bundle(hnmod)?;
        for (name, bytes) in &files {
            let to = extract_dir.join(name);
            fs::create_dir_all(to.parent().unwrap_or(&extract_dir)).map_err(|e| e.to_string())?;
            fs::write(&to, bytes).map_err(|e| format!("{}: {e}", to.display()))?;
        }
        let mixins = extract_dir.join("mixins");
        if !mixins.is_dir() {
            return Err(format!("No mixins/ folder found in {}", hnmod.display()));
        }
        // Each bundle directory is mixins/<id>/, holding horizon-mixin.toml.
        for entry in fs::read_dir(&mixins).map_err(|e| e.to_string())?.flatten() {
            if entry.path().join("horizon-mixin.toml").is_file() {
                bundle_dirs.push(entry.path());
            }
        }
    }

    if bundle_dirs.is_empty() {
        return Err("No mod bundles found in any .hnmod files".into());
    }

    // Collect every bundle into one mods dir, then apply all at once.
    let merged_mods = staging_dir.join("merged_mods");
    fs::create_dir_all(&merged_mods).map_err(|e| e.to_string())?;
    for d in &bundle_dirs {
        let name = d.file_name().unwrap_or_default();
        let target = merged_mods.join(name);
        fs::create_dir_all(&target).map_err(|e| e.to_string())?;
        copy_tree(d, &target)?;
    }

    // Apply with horizon-mixins. The output directory is cleared before use, so
    // only accept one that names its own directory and is not a shallow path.
    let out_dir = build_output_dir()?;
    if out_dir.exists() {
        fs::remove_dir_all(&out_dir).map_err(|e| e.to_string())?;
    }

    println!("Applying {} mod bundle(s)...", bundle_dirs.len());
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
        .arg("--locked")
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

/// The directory the build is written to and then compiled in. `HORIZON_BUILD_OUTPUT`
/// overrides it, but it must name its own directory (not `.`, `/`, `/tmp` or a
/// home directory): the builder clears it, and a wrong value would wipe it.
fn build_output_dir() -> Result<PathBuf, String> {
    let dir = match std::env::var("HORIZON_BUILD_OUTPUT") {
        Ok(v) => PathBuf::from(v),
        Err(_) => std::env::temp_dir().join("horizon-build-output"),
    };
    let shallow = dir.file_name().map(|n| n.is_empty()).unwrap_or(true)
        || dir
            .parent()
            .map(|p| p.as_os_str().is_empty())
            .unwrap_or(true)
        || dir == std::env::temp_dir();
    if shallow {
        return Err(format!(
            "HORIZON_BUILD_OUTPUT must be a directory of its own, not {}: the build clears it.",
            dir.display()
        ));
    }
    Ok(dir)
}

/// Read a `.hnmod` zip into validated relative paths. The rules are the
/// launcher's (`horizon_mods::index::native::Bundle::read`): no symlinks or
/// other special entries, no `..`, absolute paths, backslashes, drive letters
/// or empty segments, and a bounded total size. Nothing is executed.
fn read_bundle(path: &Path) -> Result<BTreeMap<String, Vec<u8>>, String> {
    let file = fs::File::open(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| format!("{}: {e}", path.display()))?;
    if zip.len() > 512 {
        return Err(format!("{}: too many entries", path.display()));
    }
    let mut files = BTreeMap::new();
    let mut total = 0u64;
    for i in 0..zip.len() {
        let mut entry = zip.by_index(i).map_err(|e| e.to_string())?;
        let name = entry.name().to_owned();
        if entry.is_dir() {
            continue;
        }
        if entry
            .unix_mode()
            .is_some_and(|m| m & 0o170000 != 0 && m & 0o170000 != 0o100000)
            || name.contains('\\')
            || name
                .split('/')
                .any(|p| p.is_empty() || p == "." || p == "..")
            || name.starts_with('/')
            || name.contains(':')
        {
            return Err(format!("invalid native bundle path: {name}"));
        }
        let mut bytes = Vec::new();
        (&mut entry)
            .take(MAX_FILE + 1)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        total += bytes.len() as u64;
        if total > MAX_FILE {
            return Err(format!("{}: expands beyond 64 MiB", path.display()));
        }
        if files.insert(name, bytes).is_some() {
            return Err(format!("{}: duplicate path", path.display()));
        }
    }
    if files.is_empty() {
        return Err(format!("{}: empty bundle", path.display()));
    }
    Ok(files)
}

/// Copy a bundle's tree, following no symlinks: a symlink is skipped rather
/// than copied (horizon-mixins refuses one anyway), so a crafted bundle cannot
/// pull a local file into the source that gets built.
fn copy_tree(from: &Path, to: &Path) -> Result<(), String> {
    for entry in fs::read_dir(from).map_err(|e| e.to_string())?.flatten() {
        let path = entry.path();
        let target = to.join(entry.file_name());
        let kind = entry.file_type().map_err(|e| e.to_string())?;
        if kind.is_symlink() {
            continue;
        }
        if kind.is_dir() {
            fs::create_dir_all(&target).map_err(|e| e.to_string())?;
            copy_tree(&path, &target)?;
        } else {
            fs::copy(&path, &target).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
