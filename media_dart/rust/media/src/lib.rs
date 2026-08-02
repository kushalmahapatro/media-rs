//! Video/media processing via flutter_rust_bridge.

#[cfg(feature = "frb-ffi")]
mod frb_generated;

#[cfg(not(feature = "frb-ffi"))]
mod embed_stubs;

#[cfg(not(feature = "frb-ffi"))]
pub(crate) mod frb_generated {
    pub use crate::embed_stubs::StreamSink;
}

pub mod api;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod bundled_tools;
mod gif_encoder;
mod platform;

/// Android: ART calls this when `libmedia.so` is loaded so we can attach FRB worker threads to the JVM.
#[cfg(all(target_os = "android", feature = "frb-ffi"))]
#[no_mangle]
pub unsafe extern "system" fn JNI_OnLoad(
    vm: *mut jni::sys::JavaVM,
    _reserved: *mut std::ffi::c_void,
) -> jni::sys::jint {
    platform::android::register_java_vm(vm)
}
