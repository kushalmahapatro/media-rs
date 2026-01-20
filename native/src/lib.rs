pub mod api;
mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */

use std::sync::OnceLock;
use tracing_subscriber::prelude::*;
use tracing_subscriber::{fmt, EnvFilter};

// Global guard to keep file logging alive - must be kept alive for the lifetime of the app
static LOG_GUARD: OnceLock<tracing_appender::non_blocking::WorkerGuard> = OnceLock::new();

/// Initialize logging to both console and file
/// NOTE: Disabled automatic initialization via ctor as it may interfere with FFmpeg
/// or panic handling. Logging will be initialized manually on first FFI call.
// #[ctor::ctor]
// fn init_logging() {
//     init_logging_impl();
// }

/// Manual initialization function - can be called from FFI if needed
fn init_logging_impl() {
    // Only initialize once
    static INIT: std::sync::Once = std::sync::Once::new();
    INIT.call_once(|| {
        // Determine log directory - use executable directory if available, else temp
        let log_dir = if let Ok(exe_path) = std::env::current_exe() {
            if let Some(exe_dir) = exe_path.parent() {
                exe_dir.join("logs")
            } else {
                std::env::temp_dir().join("media_rs_logs")
            }
        } else {
            std::env::temp_dir().join("media_rs_logs")
        };
        
        // Create log directory if it doesn't exist
        if let Err(e) = std::fs::create_dir_all(&log_dir) {
            // Fall back to console-only logging
            eprintln!("WARNING: Failed to create log directory {:?}: {}, using console-only logging", log_dir, e);
            let filter = EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| EnvFilter::new("debug"));
            tracing_subscriber::fmt()
                .with_env_filter(filter)
                .with_writer(std::io::stderr)
                .init();
            tracing::info!("Logging initialized (console only, file logging failed)");
            return;
        }
        
        // Set up file appender with daily rotation
        let file_appender = tracing_appender::rolling::daily(&log_dir, "media_rs");
        let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);
        
        // Store guard globally so it stays alive for the lifetime of the app
        // This is critical - if the guard is dropped, buffered logs will be lost
        LOG_GUARD.set(guard).ok();
        
        // Create env filter from RUST_LOG or default to DEBUG for maximum detail
        let filter = EnvFilter::try_from_default_env()
            .unwrap_or_else(|_| EnvFilter::new("debug"));
        
        // File layer: write everything DEBUG and above to file
        let file_layer = fmt::layer()
            .with_writer(non_blocking.with_max_level(tracing::Level::DEBUG))
            .with_ansi(false)  // No ANSI colors in file
            .with_target(true) // Include module path
            .with_file(true)   // Include file name
            .with_line_number(true) // Include line number
            .with_thread_ids(true)  // Include thread IDs
            .with_thread_names(true); // Include thread names
        
        // Console layer: write to stderr (eprintln! equivalent)
        let stderr_layer = fmt::layer()
            .with_writer(std::io::stderr)
            .with_ansi(true)  // ANSI colors in console
            .with_target(true)
            .with_filter(filter.clone());
        
        // Set up subscriber with both layers
        tracing_subscriber::registry()
            .with(filter)
            .with(file_layer)
            .with(stderr_layer)
            .init();
        
        tracing::info!("Logging initialized. Logs written to: {:?}", log_dir);
        tracing::info!("Set RUST_LOG environment variable to control log level (e.g., RUST_LOG=trace)");
    });
}

/// Manual initialization function - can be called from FFI if ctor doesn't work
/// This is a public function that can be called to ensure logging is set up
pub fn init_logging_manual() {
    init_logging_impl();
}
