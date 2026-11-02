//! Horizon's own packs, embedded in the game's binary: the first pack a player has, without
//! downloading anything (docs/shaders.md). They are ordinary packs of `packs/` in this crate,
//! read with `include_str!`, so the check judges them like any other and a test fails when one
//! stops passing it.
use crate::package::Pack;
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

/// A pack Horizon ships.
pub struct Builtin {
    /// Its folder's name in `shaderpacks/`.
    pub dir: &'static str,
    /// Every file, by path from the pack's root.
    pub files: &'static [(&'static str, &'static str)],
}

impl Builtin {
    /// This pack's files as a [`Pack`], ready for [`crate::check`].
    pub fn pack(&self) -> Result<Pack, String> {
        let files = self
            .files
            .iter()
            .map(|(path, text)| ((*path).to_owned(), text.as_bytes().to_vec()))
            .collect();
        Pack::from_files(files)
    }
}

/// Horizon's atmospheric pack: a sky stage, a material stage, bloom and a grade.
const COMPLEMENTARY: Builtin = Builtin {
    dir: "horizon_complementary",
    files: &[
        (
            crate::MANIFEST,
            include_str!("../packs/horizon_complementary/horizon-shaders.toml"),
        ),
        (
            "README.md",
            include_str!("../packs/horizon_complementary/README.md"),
        ),
        (
            "common.wgsl",
            include_str!("../packs/horizon_complementary/common.wgsl"),
        ),
        (
            "sky.wgsl",
            include_str!("../packs/horizon_complementary/sky.wgsl"),
        ),
        (
            "material.wgsl",
            include_str!("../packs/horizon_complementary/material.wgsl"),
        ),
        (
            "post/shadows.wgsl",
            include_str!("../packs/horizon_complementary/post/shadows.wgsl"),
        ),
        (
            "post/bloom.wgsl",
            include_str!("../packs/horizon_complementary/post/bloom.wgsl"),
        ),
        (
            "post/grade.wgsl",
            include_str!("../packs/horizon_complementary/post/grade.wgsl"),
        ),
    ],
};

/// The packs Horizon ships, in the order they are written.
pub fn all() -> &'static [Builtin] {
    &[COMPLEMENTARY]
}

/// Writes every built-in pack into `dir` (a `shaderpacks` folder) whose folder is missing, and
/// returns the ones it wrote. A folder that is there is left alone, so a player who edited or
/// deleted one keeps it that way.
pub fn install(dir: &Path) -> Vec<&'static str> {
    let mut wrote = Vec::new();
    for pack in all() {
        let root = dir.join(pack.dir);
        if root.exists() {
            continue;
        }
        if write(&root, pack.files).is_ok() {
            wrote.push(pack.dir);
        }
    }
    wrote
}

/// Brings the installed copies of Horizon's own packs up to date, and returns the ones it replaced.
///
/// Only a folder that is recognisably ours is touched: one whose files match the `.horizon-builtin`
/// marker we wrote, or, for a copy an older build wrote before that marker existed, one whose
/// `horizon-shaders.toml` carries the same pack id. A pack the player has edited (its files no
/// longer match the marker) is left alone, so their version wins; to keep edits, change the pack's
/// id or delete the marker. This is what makes a new shader pack reach a player who already ran an
/// older build instead of only a fresh install.
pub fn upgrade(dir: &Path) -> Vec<&'static str> {
    let mut upgraded = Vec::new();
    for pack in all() {
        let root = dir.join(pack.dir);
        if !root.is_dir() {
            continue;
        }
        let now = pack_hashes(pack.files);
        if current(&root) == now {
            continue; // Already current.
        }
        let recorded = fs::read_to_string(root.join(MANIFEST_MARKER)).ok();
        let ours = match &recorded {
            Some(text) => current(&root) == parse_manifest(text),
            None => installed_id(&root) == builtin_id(pack),
        };
        if !ours {
            continue;
        }
        if fs::remove_dir_all(&root).is_ok() && write(&root, pack.files).is_ok() {
            upgraded.push(pack.dir);
        }
    }
    upgraded
}

/// The marker listing the files a built-in pack was installed with, beside its other files.
const MANIFEST_MARKER: &str = ".horizon-builtin";

/// A pack's `id` from its `horizon-shaders.toml`, if it parses.
fn pack_id(manifest: &str) -> Option<String> {
    toml::from_str::<toml::Table>(manifest)
        .ok()?
        .get("id")?
        .as_str()
        .map(str::to_string)
}

fn installed_id(root: &Path) -> Option<String> {
    let manifest = fs::read_to_string(root.join(crate::MANIFEST)).ok()?;
    pack_id(&manifest)
}

fn builtin_id(pack: &Builtin) -> Option<String> {
    pack.files
        .iter()
        .find(|(path, _)| *path == crate::MANIFEST)
        .and_then(|(_, text)| pack_id(text))
}

fn pack_hashes(files: &[(&str, &str)]) -> BTreeMap<String, String> {
    files
        .iter()
        .map(|(path, text)| ((*path).to_owned(), hash(text.as_bytes())))
        .collect()
}

/// The hashes of every file under `root`, by path from it (no `.horizon-builtin`).
fn current(root: &Path) -> BTreeMap<String, String> {
    fn walk(root: &Path, dir: &Path, out: &mut BTreeMap<String, String>) {
        let Ok(entries) = fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(root, &path, out);
            } else if path.file_name().is_some_and(|n| n == MANIFEST_MARKER) {
                continue;
            } else if let Ok(bytes) = fs::read(&path) {
                let rel = path
                    .strip_prefix(root)
                    .unwrap_or(&path)
                    .to_string_lossy()
                    .replace('\\', "/");
                out.insert(rel, hash(&bytes));
            }
        }
    }
    let mut out = BTreeMap::new();
    walk(root, root, &mut out);
    out
}

fn parse_manifest(text: &str) -> BTreeMap<String, String> {
    text.lines()
        .filter_map(|l| {
            l.split_once("  ")
                .map(|(h, p)| (p.trim().to_owned(), h.trim().to_owned()))
        })
        .collect()
}

fn manifest_text(hashes: &BTreeMap<String, String>) -> String {
    let mut text = String::from(
        "# Written by Horizon: the files this pack was installed with. Delete this file to keep \
         your own edits from being replaced by a later built-in pack.\n",
    );
    for (path, hash) in hashes {
        text.push_str(&format!("{hash}  {path}\n"));
    }
    text
}

fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn write(root: &Path, files: &[(&str, &str)]) -> std::io::Result<()> {
    for (path, text) in files {
        let file = root.join(path);
        if let Some(parent) = file.parent() {
            fs::create_dir_all(parent)?;
        }
        fs::write(file, text)?;
    }
    let _ = fs::write(
        root.join(MANIFEST_MARKER),
        manifest_text(&pack_hashes(files)),
    );
    Ok(())
}
