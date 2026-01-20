use anyhow::{Error, Result};
use std::panic;
use std::sync::Once;
use tracing::error;

/// Enhanced error handling utilities that integrate with tracing
pub struct ErrorHandler;

impl ErrorHandler {
    /// Log an anyhow error with full context and backtrace
    pub fn log_error(err: &Error, context: &str) {
        error!(
            error = %err,
            context = %context,
            backtrace = %err.backtrace(),
            "Error occurred: {}",
            context
        );
    }

    /// Log an anyhow error with additional fields
    pub fn log_error_with_fields(
        err: &Error,
        context: &str,
        fields: &[(&str, &dyn std::fmt::Display)],
    ) {
        let event = tracing::error_span!("error", context = %context);
        let _guard = event.enter();

        error!(
            error = %err,
            backtrace = %err.backtrace(),
            "Error occurred: {}",
            context
        );

        for (key, value) in fields {
            tracing::info!(%key, %value, "Additional context");
        }
    }

    /// Convert a Result to a logged error, returning the original Result
    pub fn log_result<T>(result: Result<T>, context: &str) -> Result<T> {
        if let Err(ref err) = result {
            Self::log_error(err, context);
        }
        result
    }

    /// Execute a closure and log any errors that occur
    pub fn execute_with_logging<F, T>(f: F, context: &str) -> Result<T>
    where
        F: FnOnce() -> Result<T>,
    {
        match f() {
            Ok(result) => Ok(result),
            Err(err) => {
                Self::log_error(&err, context);
                Err(err)
            }
        }
    }

    /// Set up comprehensive panic logging for all error types
    pub fn setup_comprehensive_panic_logging() {
        static INIT: Once = Once::new();
        INIT.call_once(|| {
            let original_hook = panic::take_hook();
            panic::set_hook(Box::new(move |panic_info| {
                // Log panic information with comprehensive context
                let panic_message = panic_info
                    .payload()
                    .downcast_ref::<&str>()
                    .map(|s| *s)
                    .or_else(|| {
                        panic_info
                            .payload()
                            .downcast_ref::<String>()
                            .map(|s| s.as_str())
                    })
                    .unwrap_or("Box<dyn Any>");

                let location = panic_info
                    .location()
                    .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
                    .unwrap_or_else(|| "unknown".to_string());

                let backtrace = std::backtrace::Backtrace::capture();

                // Check if this is an anyhow error
                if let Some(err) = panic_info.payload().downcast_ref::<Error>() {
                    error!(
                        error = %err,
                        panic_message = %panic_message,
                        backtrace = %err.backtrace(),
                        panic_backtrace = %backtrace,
                        location = %location,
                        thread_id = ?std::thread::current().id(),
                        thread_name = %std::thread::current().name().unwrap_or("unnamed"),
                        "ANYHOW ERROR PANIC"
                    );
                } else {
                    // Log regular panics with enhanced context
                    error!(
                        panic_message = %panic_message,
                        location = %location,
                        backtrace = %backtrace,
                        thread_id = ?std::thread::current().id(),
                        thread_name = %std::thread::current().name().unwrap_or("unnamed"),
                        "PANIC OCCURRED"
                    );
                }

                // Call the original hook to maintain default panic behavior
                original_hook(panic_info);
            }));
        });
    }

    /// Set up panic logging for anyhow errors (deprecated - use setup_comprehensive_panic_logging)
    #[deprecated(note = "Use setup_comprehensive_panic_logging instead")]
    pub fn setup_anyhow_panic_logging() {
        Self::setup_comprehensive_panic_logging();
    }

    /// Log unhandled Results that might be silently ignored
    pub fn log_unhandled_result<T, E>(result: Result<T, E>, context: &str) -> Result<T, E>
    where
        E: std::fmt::Display + std::fmt::Debug,
    {
        if let Err(ref err) = result {
            error!(
                error = %err,
                error_debug = ?err,
                context = %context,
                backtrace = %std::backtrace::Backtrace::capture(),
                "UNHANDLED RESULT ERROR"
            );
        }
        result
    }

    /// Set up tokio runtime error handling
    pub fn setup_tokio_error_handling() {
        // This will be called when setting up the tokio runtime
        // The actual error handling is done through tracing filters
        tracing::info!("Tokio error handling configured");
    }
}

/// Extension trait for Result<T, anyhow::Error> to add logging capabilities
pub trait LoggingResultExt<T> {
    /// Log the error if the Result is Err, then return the original Result
    fn log_error(self, context: &str) -> Self;

    /// Log the error with additional fields if the Result is Err, then return the original Result
    fn log_error_with_fields(
        self,
        context: &str,
        fields: &[(&str, &dyn std::fmt::Display)],
    ) -> Self;
}

impl<T> LoggingResultExt<T> for Result<T, Error> {
    fn log_error(self, context: &str) -> Self {
        if let Err(ref err) = self {
            ErrorHandler::log_error(err, context);
        }
        self
    }

    fn log_error_with_fields(
        self,
        context: &str,
        fields: &[(&str, &dyn std::fmt::Display)],
    ) -> Self {
        if let Err(ref err) = self {
            ErrorHandler::log_error_with_fields(err, context, fields);
        }
        self
    }
}

/// Macro to easily log anyhow errors with context
#[macro_export]
macro_rules! log_anyhow_error {
    ($err:expr, $context:expr) => {
        $crate::error_handling::ErrorHandler::log_error(&$err, $context)
    };
    ($err:expr, $context:expr, $($key:expr => $value:expr),+) => {
        {
            let fields = vec![
                $(
                    ($key, &$value as &dyn std::fmt::Display)
                ),+
            ];
            $crate::error_handling::ErrorHandler::log_error_with_fields(&$err, $context, &fields)
        }
    };
}

/// Macro to execute code and automatically log any errors
#[macro_export]
macro_rules! with_error_logging {
    ($context:expr, $code:block) => {
        $crate::error_handling::ErrorHandler::execute_with_logging(|| $code, $context)
    };
}

/// Macro to log unhandled Results that might be silently ignored
#[macro_export]
macro_rules! log_unhandled {
    ($result:expr, $context:expr) => {
        let _ = $crate::error_handling::ErrorHandler::log_unhandled_result($result, $context);
    };
}

/// Macro to ensure Results are handled and logged if they fail
#[macro_export]
macro_rules! ensure_handled {
    ($result:expr, $context:expr) => {
        match $result {
            Ok(val) => val,
            Err(err) => {
                $crate::error_handling::ErrorHandler::log_error(&err, $context);
                return Err(err);
            }
        }
    };
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::anyhow;

    #[test]
    fn test_error_logging() {
        let err = anyhow!("Test error");
        ErrorHandler::log_error(&err, "test context");
        // This test mainly ensures the code compiles
        // In a real test environment, you'd verify the logs are written
    }

    #[test]
    fn test_result_logging() {
        let result: Result<i32, Error> = Err(anyhow!("Test error"));
        let logged_result = result.log_error("test context");
        assert!(logged_result.is_err());
    }
}
