use std::path::Path;

fn main() {
    let exe_name = std::env::args()
        .next()
        .and_then(|arg| {
            Path::new(&arg)
                .file_stem()
                .map(|s| s.to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| "ym".to_string());

    if exe_name == "ymc" {
        ym::run_ymc();
    } else {
        ensure_ymc();
        ym::run_ym();
    }
}

/// Ensure `ymc` binary exists next to `ym` and is up to date.
fn ensure_ymc() {
    let Ok(ym_path) = std::env::current_exe() else { return };
    let Some(dir) = ym_path.parent() else { return };

    let ymc_name = if cfg!(windows) { "ymc.exe" } else { "ymc" };
    let ymc_path = dir.join(ymc_name);

    // Skip if ymc exists and same size as ym (up to date)
    if let Ok(mb) = ymc_path.metadata() {
        if let Ok(ma) = ym_path.metadata() {
            if ma.len() == mb.len() {
                return;
            }
        }
    }

    let _ = std::fs::copy(&ym_path, &ymc_path);
}
