//! Resolve bundled `ffmpeg` / `ffprobe`.
//!
//! Linux / Windows: binaries next to `libmedia` (Dart hook + CodeAssets).
//! macOS: Mach-O executables cannot be bundled as CodeAssets through the Dart
//! native-asset pipeline (install-name / `lipo` expect dylibs). The hook copies
//! tools into `rust/media/bundled/current/` and we embed them with `include_bytes!`,
//! then materialize to a temp file on first use.

#[cfg(all(unix, not(target_os = "macos")))]
use std::ffi::{c_void, CStr};
use std::path::PathBuf;
#[cfg(target_os = "macos")]
use std::sync::OnceLock;

#[cfg(any(target_os = "linux", target_os = "windows"))]
#[no_mangle]
extern "C" fn media_dylib_path_anchor() {}

#[cfg(target_os = "macos")]
static FFMPEG_PATH: OnceLock<PathBuf> = OnceLock::new();
#[cfg(target_os = "macos")]
static FFPROBE_PATH: OnceLock<PathBuf> = OnceLock::new();

#[cfg(target_os = "macos")]
const FFMPEG_BYTES: &[u8] = include_bytes!("../bundled/current/ffmpeg");
#[cfg(target_os = "macos")]
const FFPROBE_BYTES: &[u8] = include_bytes!("../bundled/current/ffprobe");

#[cfg(target_os = "macos")]
fn materialize_executable(name: &str, bytes: &[u8]) -> PathBuf {
    use std::fs;
    use std::io::Write;
    use std::os::unix::fs::PermissionsExt;

    let root = std::env::temp_dir().join("media_ffmpeg_tools");
    fs::create_dir_all(&root).unwrap_or(());
    let p = root.join(name);
    let needs_write = match fs::metadata(&p) {
        Ok(m) => m.len() != bytes.len() as u64,
        Err(_) => true,
    };
    if needs_write {
        let mut f = fs::File::create(&p).unwrap_or_else(|e| {
            panic!("failed to create {p:?}: {e}");
        });
        f.write_all(bytes).unwrap_or_else(|e| panic!("failed to write {p:?}: {e}"));
        f.sync_all().ok();
        let mut perms = fs::metadata(&p).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&p, perms).unwrap_or_else(|e| panic!("chmod {p:?}: {e}"));
    }
    p
}

#[cfg(any(target_os = "linux", target_os = "windows"))]
fn sibling_tool(name: &str) -> PathBuf {
    let ext = if cfg!(target_os = "windows") { ".exe" } else { "" };
    let dir = dylib_parent_dir().unwrap_or_else(|| {
        panic!(
            "could not resolve the directory containing libmedia; ffmpeg/ffprobe must live next to the library"
        )
    });
    let p = dir.join(format!("{name}{ext}"));
    if !p.is_file() {
        panic!(
            "bundled {name}{ext} not found next to libmedia at {}. Build native assets so the Dart hook places ffmpeg/ffprobe beside the library.",
            p.display()
        );
    }
    p
}

#[cfg(all(unix, not(target_os = "macos")))]
fn dylib_parent_dir() -> Option<PathBuf> {
    use libc::{dladdr, Dl_info};

    let mut info: Dl_info = unsafe { std::mem::zeroed() };
    let ok = unsafe { dladdr(media_dylib_path_anchor as *const c_void, &mut info) };
    if ok == 0 || info.dli_fname.is_null() {
        return None;
    }
    let s = unsafe { CStr::from_ptr(info.dli_fname) };
    let path = PathBuf::from(s.to_string_lossy().as_ref());
    path.parent().map(|p| p.to_path_buf())
}

#[cfg(windows)]
use std::ffi::c_void;

#[cfg(windows)]
fn dylib_parent_dir() -> Option<PathBuf> {
    use std::os::windows::ffi::OsStringExt;
    use windows_sys::Win32::Foundation::HMODULE;
    use windows_sys::Win32::System::LibraryLoader::{
        GetModuleFileNameW, GetModuleHandleExW, GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
    };

    let mut module: HMODULE = std::ptr::null_mut();
    let flags = GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT;
    let ok = unsafe {
        GetModuleHandleExW(
            flags,
            media_dylib_path_anchor as *const c_void,
            &mut module as *mut HMODULE,
        )
    };
    if ok == 0 || module.is_null() {
        return None;
    }
    let mut buf = vec![0u16; 1024];
    let len = unsafe { GetModuleFileNameW(module, buf.as_mut_ptr(), buf.len() as u32) } as usize;
    if len == 0 {
        return None;
    }
    buf.truncate(len);
    let os = std::ffi::OsString::from_wide(&buf);
    PathBuf::from(os).parent().map(std::path::Path::to_path_buf)
}

/// Bundled `ffmpeg` path; no `PATH` fallback.
pub fn ffmpeg_path() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        FFMPEG_PATH
            .get_or_init(|| materialize_executable("ffmpeg", FFMPEG_BYTES))
            .clone()
    }
    #[cfg(not(target_os = "macos"))]
    {
        sibling_tool("ffmpeg")
    }
}

/// Bundled `ffprobe` path; no `PATH` fallback.
pub fn ffprobe_path() -> PathBuf {
    #[cfg(target_os = "macos")]
    {
        FFPROBE_PATH
            .get_or_init(|| materialize_executable("ffprobe", FFPROBE_BYTES))
            .clone()
    }
    #[cfg(not(target_os = "macos"))]
    {
        sibling_tool("ffprobe")
    }
}
