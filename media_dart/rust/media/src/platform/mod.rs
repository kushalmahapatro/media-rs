#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
pub mod desktop;
#[cfg(target_os = "android")]
pub mod android;
#[cfg(target_os = "ios")]
pub mod ios;
