//! Stub implementations for non-Android platforms.
//!
//! The mediacodec crate is fundamentally Android-only, but it gets resolved
//! as a path dependency on all platforms. These stub types allow compilation
//! to succeed on Windows/Linux/macOS without the Android NDK.

#[repr(C)]
#[derive(Debug)]
pub struct ANativeWindow {
    _priv: [u8; 0],
    _marker: core::marker::PhantomData<(*mut u8, core::marker::PhantomPinned)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativeWindowFormat {
    Rgba8 = 1,
    Rgb8 = 2,
    Rgb565 = 4,
    Yuv420 = 0x23,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub enum NativeWindowTransform {
    Identity = 0x00,
}

#[repr(C)]
#[derive(Debug)]
pub struct NativeWindowBuffer {
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub format: i32,
    pub bits: *mut std::ffi::c_void,
}

#[repr(C)]
pub struct ARect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

#[derive(Debug)]
pub struct NativeWindow {
    pub(crate) inner: *mut ANativeWindow,
}

impl NativeWindow {
    pub fn from_raw(inner: *mut ANativeWindow) -> Self {
        Self { inner }
    }

    pub fn width(&self) -> i32 {
        0
    }

    pub fn height(&self) -> i32 {
        0
    }

    pub fn format(&self) -> NativeWindowFormat {
        NativeWindowFormat::Other
    }

    pub fn set_geometry(&mut self, _width: i32, _height: i32, _format: NativeWindowFormat) {}
}

impl Clone for NativeWindow {
    fn clone(&self) -> Self {
        Self { inner: self.inner }
    }
}

// Stub for codec.rs -> ANativeWindow_fromSurface
#[cfg(not(target_os = "android"))]
fn stub_ANativeWindow_fromSurface(_env: *mut std::ffi::c_void, _surface: *mut std::ffi::c_void) -> *mut ANativeWindow {
    std::ptr::null_mut()
}
