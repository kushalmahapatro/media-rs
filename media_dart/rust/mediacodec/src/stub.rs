//! Stub implementations for non-Android platforms.
//! The mediacodec crate is fundamentally Android-only but gets resolved as a path
//! dependency on all platforms. These stub types allow compilation to succeed on Windows.

use std::ffi::c_void;

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NativeWindowFormat {
    Rgba8 = 1,
    Rgb8 = 2,
    Rgb565 = 4,
    Yuv420 = 0x23,
    Other,
}

impl NativeWindowFormat {
    pub fn values() -> Vec<Self> {
        vec![Self::Rgba8, Self::Rgb8, Self::Rgb565, Self::Yuv420]
    }
}

impl From<isize> for NativeWindowFormat {
    fn from(value: isize) -> Self {
        for item in Self::values() {
            if item as isize == value {
                return item;
            }
        }
        Self::Other
    }
}

impl std::ops::BitOr for NativeWindowFormat {
    type Output = isize;
    fn bitor(self, rhs: Self) -> Self::Output {
        (self as isize) | (rhs as isize)
    }
}

#[repr(C)]
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NativeWindowTransform {
    Identity = 0x00,
}

impl NativeWindowTransform {
    pub fn mirror_horizontal() -> Self {
        Self::Identity
    }
    pub fn mirror_vertical() -> Self {
        Self::Identity
    }
    pub fn rotate90() -> Self {
        Self::Identity
    }
    pub fn rotate180() -> Self {
        Self::Identity
    }
    pub fn rotate270() -> Self {
        Self::Identity
    }
}

impl std::ops::BitOr for NativeWindowTransform {
    type Output = isize;
    fn bitor(self, _rhs: Self) -> Self::Output {
        self as isize
    }
}

#[repr(C)]
#[derive(Debug, Clone)]
pub struct NativeWindowBuffer {
    pub width: i32,
    pub height: i32,
    pub stride: i32,
    pub format: i32,
    pub bits: *mut c_void,
}

impl NativeWindowBuffer {
    pub fn new() -> Self {
        Self {
            width: 0,
            height: 0,
            stride: 0,
            format: 0,
            bits: std::ptr::null_mut(),
        }
    }
}

impl Default for NativeWindowBuffer {
    fn default() -> Self {
        Self::new()
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub struct ARect {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

impl ARect {
    pub fn new() -> Self {
        Self {
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
        }
    }
}

impl Default for ARect {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug)]
pub struct ANativeWindow(*mut c_void);

impl ANativeWindow {
    pub fn null() -> Self {
        Self(std::ptr::null_mut())
    }
}

#[derive(Debug)]
pub struct NativeWindow {
    inner: *mut ANativeWindow,
}

impl NativeWindow {
    pub fn null() -> Self {
        Self {
            inner: std::ptr::null_mut(),
        }
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
}

impl Default for NativeWindow {
    fn default() -> Self {
        Self::null()
    }
}

impl Clone for NativeWindow {
    fn clone(&self) -> Self {
        Self { inner: self.inner }
    }
}
