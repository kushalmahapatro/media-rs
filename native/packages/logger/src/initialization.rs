use tracing::{info};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt, EnvFilter, Registry};
use tracing_subscriber::fmt::layer;

use crate::error_handling::ErrorHandler;

/// Initialize comprehensive error tracing and panic capture for the entire application
/// This should be called once at application startup before any other operations
pub fn initialize_comprehensive_error_tracing() -> Result<(), Box<dyn std::error::Error>> {
    // Set up tracing subscriber with comprehensive logging
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    let fmt_layer = layer()
        .with_target(true)
        .with_thread_ids(true)
        .with_thread_names(true)
        .with_file(true)
        .with_line_number(true)
        .with_span_events(tracing_subscriber::fmt::format::FmtSpan::FULL);

    Registry::default()
        .with(env_filter)
        .with(fmt_layer)
        .try_init()
        .map_err(|e| format!("Failed to initialize tracing: {}", e))?;

    info!("Tracing subscriber initialized");

    // Set up comprehensive panic logging
    ErrorHandler::setup_comprehensive_panic_logging();
    info!("Comprehensive panic logging configured");

    // Set up tokio runtime error handling
    ErrorHandler::setup_tokio_error_handling();
    info!("Tokio error handling configured");

    // Log successful initialization
    info!(
        thread_id = ?std::thread::current().id(),
        thread_name = %std::thread::current().name().unwrap_or("main"),
        "Comprehensive error tracing system initialized successfully"
    );

    Ok(())
}

/// Initialize error tracing with custom log level
pub fn initialize_error_tracing_with_level(level: &str) -> Result<(), Box<dyn std::error::Error>> {
    let env_filter = EnvFilter::new(level);

    let fmt_layer = layer()
        .with_target(true)
        .with_thread_ids(true)
        .with_thread_names(true)
        .with_file(true)
        .with_line_number(true)
        .with_span_events(tracing_subscriber::fmt::format::FmtSpan::FULL);

    Registry::default()
        .with(env_filter)
        .with(fmt_layer)
        .try_init()
        .map_err(|e| format!("Failed to initialize tracing: {}", e))?;

    info!("Tracing subscriber initialized with level: {}", level);

    // Set up comprehensive panic logging
    ErrorHandler::setup_comprehensive_panic_logging();
    info!("Comprehensive panic logging configured");

    // Set up tokio runtime error handling
    ErrorHandler::setup_tokio_error_handling();
    info!("Tokio error handling configured");

    info!(
        "Error tracing system initialized with custom level: {}",
        level
    );

    Ok(())
}

/// Initialize error tracing for development with debug level
pub fn initialize_development_error_tracing() -> Result<(), Box<dyn std::error::Error>> {
    initialize_error_tracing_with_level("debug")
}

/// Initialize error tracing for production with info level
pub fn initialize_production_error_tracing() -> Result<(), Box<dyn std::error::Error>> {
    initialize_error_tracing_with_level("info")
}

/// Initialize error tracing for testing with trace level
pub fn initialize_test_error_tracing() -> Result<(), Box<dyn std::error::Error>> {
    initialize_error_tracing_with_level("trace")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_initialization_functions_exist() {
        // These tests mainly ensure the functions compile and can be called
        // In a real test environment, you'd verify the tracing is actually set up
        assert!(initialize_error_tracing_with_level("debug").is_ok());
    }
}
