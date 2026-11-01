//! The shader packs in the `shaderpacks` folder beside `options.txt`, as Options > Horizon
//! Settings > Shader Packs lists them: Horizon's own (docs/shaders.md) and those in the
//! `shaders/` format, side by side.

use std::path::Path;

pub const DIR: &str = "shaderpacks";

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// A folder with `horizon-shaders.toml`, or a `.hshader`.
    Horizon,
    /// A folder with a `shaders` folder, or a `.zip`.
    Classic,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Entry {
    /// The folder's or file's name in `shaderpacks`: what the pick saves.
    pub file: String,
    /// The pack's own name for Horizon's packs, else `file`.
    pub title: String,
    pub kind: Kind,
}

/// The packs in `dir`, Horizon's first, each kind by title. A missing folder has none.
pub fn scan(dir: &Path) -> Vec<Entry> {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut packs: Vec<Entry> = entries.flatten().filter_map(|e| entry(&e.path())).collect();
    packs.sort_by(|a, b| {
        (a.kind == Kind::Classic, a.title.to_lowercase())
            .cmp(&(b.kind == Kind::Classic, b.title.to_lowercase()))
    });
    packs
}

/// The packs in `dir` after writing Horizon's own packs there when they are missing
/// (`horizon_shader_api::builtin`): what the Shader Packs screens list, so a fresh install has a
/// pack to try without downloading one. A built-in pack the player edited or deleted is left as
/// it is.
pub fn scan_installing_builtin(dir: &Path) -> Vec<Entry> {
    if std::fs::create_dir_all(dir).is_ok() {
        horizon_shader_api::builtin::install(dir);
    }
    scan(dir)
}

fn entry(path: &Path) -> Option<Entry> {
    let file = path.file_name()?.to_str()?.to_owned();
    if file.starts_with('.') {
        return None;
    }
    if horizon_shader_api::package::is_pack(path) {
        // Its manifest's name; a pack that can't be read is still listed, under its file
        // name: picking it says why in the chat.
        let manifest = if path.is_dir() {
            std::fs::read_to_string(path.join(horizon_shader_api::MANIFEST))
                .ok()
                .and_then(|t| horizon_shader_api::Manifest::parse(&t).ok())
        } else {
            horizon_shader_api::Pack::read(path)
                .ok()
                .map(|p| p.manifest)
        };
        let title = manifest.map_or_else(|| file.clone(), |m| m.name);
        return Some(Entry {
            file,
            title,
            kind: Kind::Horizon,
        });
    }
    let zip = path.is_file()
        && path
            .extension()
            .is_some_and(|e| e.eq_ignore_ascii_case("zip"));
    (zip || path.join("shaders").is_dir()).then(|| Entry {
        title: file.clone(),
        file,
        kind: Kind::Classic,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_both_kinds_horizon_first_and_skips_the_rest() {
        let dir = std::env::temp_dir().join(format!("horizon-shader-list-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let d = dir.as_path();
        let manifest = "schema = 1\nid = \"warm\"\nname = \"Warm Light\"\nversion = \"1\"\n\
            api = \"0.1\"\n[[post]]\nfile = \"p.wgsl\"\n";
        std::fs::create_dir(d.join("warm")).unwrap();
        std::fs::write(d.join("warm").join(horizon_shader_api::MANIFEST), manifest).unwrap();
        std::fs::create_dir_all(d.join("Classic Folder/shaders")).unwrap();
        std::fs::write(d.join("archive.zip"), b"").unwrap();
        std::fs::write(d.join("notes.txt"), b"").unwrap();
        std::fs::create_dir(d.join("empty")).unwrap();
        std::fs::create_dir_all(d.join(".hidden/shaders")).unwrap();
        let packs = scan(d);
        let listed: Vec<(&str, &str, Kind)> = packs
            .iter()
            .map(|e| (e.file.as_str(), e.title.as_str(), e.kind))
            .collect();
        assert_eq!(
            listed,
            [
                ("warm", "Warm Light", Kind::Horizon),
                ("archive.zip", "archive.zip", Kind::Classic),
                ("Classic Folder", "Classic Folder", Kind::Classic),
            ]
        );
        assert!(scan(&d.join("missing")).is_empty());
        std::fs::remove_dir_all(d).unwrap();
    }

    #[test]
    fn installs_horizons_own_packs_once_and_lists_them() {
        let dir =
            std::env::temp_dir().join(format!("horizon-shader-builtin-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let packs = scan_installing_builtin(&dir);
        let builtin: Vec<(&str, Kind)> = packs
            .iter()
            .map(|e| (e.file.as_str(), e.kind))
            .filter(|(_, kind)| *kind == Kind::Horizon)
            .collect();
        assert_eq!(builtin, [("horizon_complementary", Kind::Horizon)]);
        let title = packs[0].title.as_str();
        assert_eq!(title, "Horizon Complementary");
        // Every stage's file is there, so the game can load the pack it lists.
        for file in [
            "common.wgsl",
            "sky.wgsl",
            "material.wgsl",
            "post/bloom.wgsl",
            "post/grade.wgsl",
        ] {
            assert!(
                dir.join("horizon_complementary").join(file).is_file(),
                "{file}"
            );
        }
        // A pack that is there is left alone: deleting one keeps it deleted.
        std::fs::remove_dir_all(dir.join("horizon_complementary")).unwrap();
        std::fs::create_dir_all(dir.join("horizon_complementary")).unwrap();
        assert!(scan_installing_builtin(&dir).is_empty());
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
