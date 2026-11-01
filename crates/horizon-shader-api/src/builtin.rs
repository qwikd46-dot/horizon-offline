//! Horizon's own packs, embedded in the game's binary: the first pack a player has, without
//! downloading anything (docs/shaders.md). They are ordinary packs of `packs/` in this crate,
//! read with `include_str!`, so the check judges them like any other and a test fails when one
//! stops passing it.
use crate::package::Pack;
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

fn write(root: &Path, files: &[(&str, &str)]) -> std::io::Result<()> {
    for (path, text) in files {
        let file = root.join(path);
        if let Some(parent) = file.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::write(file, text)?;
    }
    Ok(())
}
