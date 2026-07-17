//! Video/media processing via flutter_rust_bridge.

mod frb_generated;
pub mod api;
#[cfg(any(target_os = "linux", target_os = "macos", target_os = "windows"))]
mod bundled_tools;
mod gif_encoder;
mod platform;

/// Android: ART calls this when `libmedia.so` is loaded so we can attach FRB worker threads to the JVM.
#[cfg(target_os = "android")]
#[no_mangle]
pub unsafe extern "system" fn JNI_OnLoad(
    vm: *mut jni::sys::JavaVM,
    _reserved: *mut std::ffi::c_void,
) -> jni::sys::jint {
    platform::android::register_java_vm(vm)
}
