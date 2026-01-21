use std::process::Command;

fn parse_modversion(version: &str) -> Option<(u32, u32)> {
    // Example: "62.11.100" => (62, 11)
    let mut it = version.trim().split('.');
    let major = it.next()?.parse().ok()?;
    let minor = it.next()?.parse().ok()?;
    Some((major, minor))
}

fn main() {
    // ffmpeg-next uses cfg gates like:
    //   #[cfg(ffmpeg_8_0)]
    //   #[cfg(feature = "ffmpeg_7_0")]
    //
    // Cargo features/cfgs from ffmpeg-sys-next do NOT automatically propagate to this crate, so
    // we must detect the linked FFmpeg version ourselves and set the appropriate cfg flags.

    let ffmpeg_lavc_versions = [
        ("ffmpeg_3_0", 57, 24),
        ("ffmpeg_3_1", 57, 48),
        ("ffmpeg_3_2", 57, 64),
        ("ffmpeg_3_3", 57, 89),
        ("ffmpeg_3_1", 57, 107),
        ("ffmpeg_4_0", 58, 18),
        ("ffmpeg_4_1", 58, 35),
        ("ffmpeg_4_2", 58, 54),
        ("ffmpeg_4_3", 58, 91),
        ("ffmpeg_4_4", 58, 100),
        ("ffmpeg_5_0", 59, 18),
        ("ffmpeg_5_1", 59, 37),
        ("ffmpeg_6_0", 60, 3),
        ("ffmpeg_6_1", 60, 31),
        ("ffmpeg_7_0", 61, 3),
        ("ffmpeg_7_1", 61, 19),
        ("ffmpeg_8_0", 62, 8),
    ];

    // Tell rustc these cfg values are expected (avoids `unexpected_cfgs` warnings).
    for &(flag, _, _) in ffmpeg_lavc_versions.iter() {
        println!(r#"cargo:rustc-check-cfg=cfg({flag})"#);
        println!(r#"cargo:rustc-check-cfg=cfg(feature, values("{flag}"))"#);
    }

    // Determine libavcodec version via pkg-config.
    // Prefer the PKG_CONFIG env var if present.
    let pkg_config = std::env::var("PKG_CONFIG").unwrap_or_else(|_| "pkg-config".to_string());
    let modversion = Command::new(pkg_config)
        .args(["--modversion", "libavcodec"])
        .output()
        .ok()
        .and_then(|o| if o.status.success() { Some(o) } else { None })
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();

    if let Some((lavc_major, lavc_minor)) = parse_modversion(&modversion) {
        // Enable ONLY the highest matching flag.
        //
        // Important: this crate sometimes has separate cfg blocks for `feature="ffmpeg_7_0"` and
        // `ffmpeg_8_0`. If we enable multiple version flags at once, those blocks overlap and
        // can cause compilation errors (non-unit statement expressions, duplicate field init, etc).
        let mut selected: Option<&'static str> = None;
        for &(flag, major_req, minor_req) in ffmpeg_lavc_versions.iter() {
            if lavc_major > major_req || (lavc_major == major_req && lavc_minor >= minor_req) {
                selected = Some(flag);
            }
        }
        if let Some(flag) = selected {
            println!(r#"cargo:rustc-cfg={flag}"#);
            println!(r#"cargo:rustc-cfg=feature="{flag}""#);
        }
        println!(
            "cargo:warning=Detected libavcodec version {}.{} via pkg-config (modversion='{}')",
            lavc_major,
            lavc_minor,
            modversion.trim()
        );
    } else {
        // Fallback: if we cannot detect, assume FFmpeg 8 (matches this repo’s vendored build).
        println!(r#"cargo:rustc-cfg=ffmpeg_8_0"#);
        println!(r#"cargo:rustc-cfg=feature="ffmpeg_8_0""#);
        println!(
            "cargo:warning=Could not detect libavcodec version via pkg-config (modversion='{}'); assuming ffmpeg_8_0",
            modversion.trim()
        );
    }
}
