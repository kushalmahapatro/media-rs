use crate::api::media::{self, ThumbnailParams};
use libc::c_char;
use std::ffi::{CStr, CString};

#[repr(C)]
pub struct CVideoInfo {
    pub duration_ms: u64,
    pub width: u32,
    pub height: u32,
    pub size_bytes: u64,
    pub has_bitrate: bool,
    pub bitrate: u64,
    pub codec_name: *mut c_char,
    pub format_name: *mut c_char,
}

#[repr(C)]
pub struct CBuffer {
    pub data: *mut u8,
    pub len: u64,
}

#[no_mangle]
pub extern "C" fn media_get_video_info(path: *const c_char) -> *mut CVideoInfo {
    let c_str = unsafe {
        if path.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(path)
    };

    let path_str = match c_str.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return std::ptr::null_mut(),
    };

    match media::get_video_info(path_str) {
        Ok(info) => {
            let c_info = Box::new(CVideoInfo {
                duration_ms: info.duration_ms,
                width: info.width,
                height: info.height,
                size_bytes: info.size_bytes,
                has_bitrate: info.bitrate.is_some(),
                bitrate: info.bitrate.unwrap_or(0),
                codec_name: info
                    .codec_name
                    .map(|s| CString::new(s).unwrap().into_raw())
                    .unwrap_or(std::ptr::null_mut()),
                format_name: info
                    .format_name
                    .map(|s| CString::new(s).unwrap().into_raw())
                    .unwrap_or(std::ptr::null_mut()),
            });
            Box::into_raw(c_info)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn media_generate_thumbnail(
    path: *const c_char,
    time_ms: u64,
    max_width: u32,
    max_height: u32,
) -> *mut CBuffer {
    let c_str = unsafe {
        if path.is_null() {
            return std::ptr::null_mut();
        }
        CStr::from_ptr(path)
    };

    let path_str = match c_str.to_str() {
        Ok(s) => s.to_string(),
        Err(_) => return std::ptr::null_mut(),
    };

    let params = ThumbnailParams {
        time_ms,
        max_width,
        max_height,
    };

    match media::generate_thumbnail(path_str, params) {
        Ok(bytes) => {
            let mut boxed_slice = bytes.into_boxed_slice();
            let len = boxed_slice.len() as u64;
            let data = boxed_slice.as_mut_ptr();
            std::mem::forget(boxed_slice); // Leak memory, managed by CBuffer

            let buffer = Box::new(CBuffer { data, len });
            Box::into_raw(buffer)
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn media_free_video_info(ptr: *mut CVideoInfo) {
    if ptr.is_null() {
        return;
    }
    let info = Box::from_raw(ptr);
    if !info.codec_name.is_null() {
        let _ = CString::from_raw(info.codec_name);
    }
    if !info.format_name.is_null() {
        let _ = CString::from_raw(info.format_name);
    }
}

#[no_mangle]
pub unsafe extern "C" fn media_free_buffer(ptr: *mut CBuffer) {
    if ptr.is_null() {
        return;
    }
    let buf = Box::from_raw(ptr);
    if !buf.data.is_null() {
        // Reconstruct the slice to drop it
        let _ = std::slice::from_raw_parts_mut(buf.data, buf.len as usize);
        // We actually need to reconstruct the Vec or Box<[u8]> to deallocate correctly?
        // Specifically we called into_boxed_slice -> as_mut_ptr.
        // So we should:
        let _ = Box::from_raw(std::slice::from_raw_parts_mut(buf.data, buf.len as usize));
    }
}
