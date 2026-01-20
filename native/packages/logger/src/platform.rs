use crate::error_handling::ErrorHandler;
use std::env::set_var;
use std::sync::OnceLock;
use tracing_appender::rolling::{RollingFileAppender, Rotation};
use tracing_core::Subscriber;
use tracing_subscriber::{
    field::RecordFields,
    fmt::{
        self,
        format::{DefaultFields, Writer},
        time::FormatTime,
        FormatEvent, FormatFields, FormattedFields,
    },
    layer::{Layered, SubscriberExt as _},
    registry::LookupSpan,
    reload::{self, Handle},
    util::SubscriberInitExt as _,
    EnvFilter, Layer, Registry,
};

struct EventFormatter {
    pub display_timestamp: bool,
    pub display_level: bool,
}

impl EventFormatter {
    fn new() -> Self {
        Self {
            display_timestamp: true,
            display_level: true,
        }
    }

    #[cfg(target_os = "android")]
    fn for_logcat() -> Self {
        // Level and time are already captured by logcat separately
        Self {
            display_timestamp: false,
            display_level: false,
        }
    }

    fn format_timestamp(&self, writer: &mut Writer<'_>) -> std::fmt::Result {
        if fmt::time::SystemTime.format_time(writer).is_err() {
            writer.write_str("<unknown time>")?;
        }
        Ok(())
    }

    fn write_filename(&self, writer: &mut Writer<'_>, filename: &str) -> std::fmt::Result {
        const CRATES_IO_PATH_MATCHER: &str = ".cargo/registry/src/index.crates.io";
        let crates_io_filename = filename
            .split_once(CRATES_IO_PATH_MATCHER)
            .and_then(|(_, rest)| rest.split_once('/').map(|(_, rest)| rest));

        if let Some(filename) = crates_io_filename {
            writer.write_str("<crates.io>/")?;
            writer.write_str(filename)
        } else {
            writer.write_str(filename)
        }
    }
}

impl<S, N> FormatEvent<S, N> for EventFormatter
where
    S: Subscriber + for<'a> LookupSpan<'a>,
    N: for<'a> FormatFields<'a> + 'static,
{
    fn format_event(
        &self,
        ctx: &fmt::FmtContext<'_, S, N>,
        mut writer: Writer<'_>,
        event: &tracing_core::Event<'_>,
    ) -> std::fmt::Result {
        let meta = event.metadata();

        if self.display_timestamp {
            self.format_timestamp(&mut writer)?;
            writer.write_char(' ')?;
        }

        if self.display_level {
            // For info and warn, add a padding space to the left
            write!(writer, "{:>5} ", meta.level())?;
        }

        write!(writer, "{}: ", meta.target())?;

        ctx.format_fields(writer.by_ref(), event)?;

        if let Some(filename) = meta.file() {
            writer.write_str(" | ")?;
            self.write_filename(&mut writer, filename)?;
            if let Some(line_number) = meta.line() {
                write!(writer, ":{line_number}")?;
            }
        }

        if let Some(scope) = ctx.event_scope() {
            writer.write_str(" | spans: ")?;

            let mut first = true;

            for span in scope.from_root() {
                if !first {
                    writer.write_str(" > ")?;
                }

                first = false;

                write!(writer, "{}", span.name())?;

                if let Some(fields) = &span.extensions().get::<FormattedFields<N>>() {
                    if !fields.is_empty() {
                        write!(writer, "{{{fields}}}")?;
                    }
                }
            }
        }

        writeln!(writer)
    }
}

// Another fields formatter is necessary because of this bug
// https://github.com/tokio-rs/tracing/issues/1372. Using a new
// formatter for the fields forces to record them in different span
// extensions, and thus remove the duplicated fields in the span.
#[derive(Default)]
struct FieldsFormatterForFiles(DefaultFields);

impl<'writer> FormatFields<'writer> for FieldsFormatterForFiles {
    fn format_fields<R: RecordFields>(
        &self,
        writer: Writer<'writer>,
        fields: R,
    ) -> std::fmt::Result {
        self.0.format_fields(writer, fields)
    }
}

type ReloadHandle = Handle<
    tracing_subscriber::fmt::Layer<
        Layered<EnvFilter, Registry>,
        FieldsFormatterForFiles,
        EventFormatter,
        RollingFileAppender,
    >,
    Layered<EnvFilter, Registry>,
>;
fn text_layers(
    config: TracingConfiguration,
) -> (
    impl Layer<Layered<EnvFilter, Registry>>,
    Option<ReloadHandle>,
) {
    let (file_layer, reload_handle) = if let Some(c) = config.write_to_files {
        eprintln!("Creating file layer with configuration: path={}, prefix={}, suffix={:?}, max_files={:?}",
            c.path, c.file_prefix, c.file_suffix, c.max_files);
        match make_file_layer(c) {
            Ok(layer) => {
                eprintln!("File layer created successfully");
                let (reload_layer, handle) = reload::Layer::new(layer);
                (Some(reload_layer), Some(handle))
            }
            Err(e) => {
                eprintln!("Failed to create file layer: {}", e);
                eprintln!("Falling back to no-op file layer");
                (None, None)
            }
        }
    } else {
        (None, None)
    };

    let layers = Layer::and_then(
        file_layer,
        config.write_to_stdout_or_system.then(|| {
            // Another fields formatter is necessary because of this bug
            // https://github.com/tokio-rs/tracing/issues/1372. Using a new
            // formatter for the fields forces to record them in different span
            // extensions, and thus remove the duplicated fields in the span.
            #[derive(Default)]
            struct FieldsFormatterFormStdoutOrSystem(DefaultFields);

            impl<'writer> FormatFields<'writer> for FieldsFormatterFormStdoutOrSystem {
                fn format_fields<R: RecordFields>(
                    &self,
                    writer: Writer<'writer>,
                    fields: R,
                ) -> std::fmt::Result {
                    self.0.format_fields(writer, fields)
                }
            }

            #[cfg(not(target_os = "android"))]
            return fmt::layer()
                .fmt_fields(FieldsFormatterFormStdoutOrSystem::default())
                .event_format(EventFormatter::new())
                // See comment above.
                .with_ansi(false)
                .with_writer(std::io::stderr);

            #[cfg(target_os = "android")]
            return fmt::layer()
                .fmt_fields(FieldsFormatterFormStdoutOrSystem::default())
                .event_format(EventFormatter::for_logcat())
                // See comment above.
                .with_ansi(false)
                .with_writer(paranoid_android::AndroidLogMakeWriter::new(
                    "messaging".to_owned(),
                ));
        }),
    );

    (layers, reload_handle)
}
fn make_file_layer(
    file_configuration: TracingFileConfiguration,
) -> Result<
    fmt::Layer<
        Layered<EnvFilter, Registry, Registry>,
        FieldsFormatterForFiles,
        EventFormatter,
        RollingFileAppender,
    >,
    String,
> {
    eprintln!(
        "make_file_layer: Starting with path: {}",
        file_configuration.path
    );

    let path = std::path::Path::new(&file_configuration.path);
    eprintln!("make_file_layer: Path exists: {}", path.exists());
    eprintln!("make_file_layer: Path is absolute: {}", path.is_absolute());
    eprintln!("make_file_layer: Path parent: {:?}", path.parent());

    if !path.exists() {
        eprintln!(
            "make_file_layer: Directory doesn't exist, creating: {}",
            file_configuration.path
        );
        match std::fs::create_dir_all(path) {
            Ok(_) => eprintln!("make_file_layer: Directory created successfully"),
            Err(e) => {
                eprintln!("make_file_layer: Failed to create directory: {}", e);
                return Err(format!(
                    "Failed to create log directory '{}': {}",
                    file_configuration.path, e
                ));
            }
        }
    } else {
        eprintln!(
            "make_file_layer: Directory already exists: {}",
            file_configuration.path
        );
    }

    eprintln!(
        "make_file_layer: Building RollingFileAppender with prefix: {}",
        file_configuration.file_prefix
    );
    let mut builder = RollingFileAppender::builder()
        .rotation(Rotation::DAILY)
        .filename_prefix(&file_configuration.file_prefix);

    if let Some(max_files) = file_configuration.max_files {
        eprintln!("make_file_layer: Setting max files: {}", max_files);
        builder = builder.max_log_files(max_files as usize)
    }
    if let Some(file_suffix) = file_configuration.file_suffix {
        eprintln!("make_file_layer: Setting file suffix: {}", file_suffix);
        builder = builder.filename_suffix(file_suffix)
    }

    eprintln!(
        "make_file_layer: Building appender for path: {}",
        file_configuration.path
    );
    let writer: Result<RollingFileAppender, tracing_appender::rolling::InitError> =
        builder.build(&file_configuration.path);

    match writer {
        Ok(writer) => {
            eprintln!("make_file_layer: RollingFileAppender created successfully");
            let formatter = fmt::layer()
                .fmt_fields(FieldsFormatterForFiles::default())
                .event_format(EventFormatter::new())
                .with_ansi(false)
                .with_writer(writer);

            eprintln!("make_file_layer: Formatter layer created successfully");
            Ok(formatter)
        }
        Err(e) => {
            eprintln!(
                "make_file_layer: Failed to create RollingFileAppender: {}",
                e
            );
            Err(format!("Failed to create a rolling file appender: {}", e))
        }
    }
}

/// Configuration to save logs to (rotated) log-files.
#[derive(Debug)]
pub struct TracingFileConfiguration {
    /// Base location for all the log files.
    pub path: String,

    /// Prefix for the log files' names.
    pub file_prefix: String,

    /// Optional suffix for the log file's names.
    pub file_suffix: Option<String>,

    /// Maximum number of rotated files.
    ///
    /// If not set, there's no max limit, i.e. the number of log files is
    /// unlimited.
    pub max_files: Option<u64>,
}

struct LoggingCtx {
    reload_handle: Option<ReloadHandle>,
}
static LOGGING: OnceLock<LoggingCtx> = OnceLock::new();

pub struct TracingConfiguration {
    /// The desired log level.
    pub log_level: crate::tracing::LogLevel,

    /// Whether to log to stdout, or in the logcat on Android.
    pub write_to_stdout_or_system: bool,

    /// If set, configures rotated log files where to write additional logs.
    pub write_to_files: Option<TracingFileConfiguration>,
}

impl TracingConfiguration {
    /// Sets up the tracing configuration and return a [`Logger`] instance
    /// holding onto it.
    #[allow(unused_mut)]
    fn build(mut self) -> LoggingCtx {
        eprintln!("TracingConfiguration::build: Starting initialization");
        eprintln!(
            "TracingConfiguration::build: Log level: {:?}",
            self.log_level
        );
        eprintln!(
            "TracingConfiguration::build: Write to stdout/system: {}",
            self.write_to_stdout_or_system
        );
        eprintln!(
            "TracingConfiguration::build: Write to files: {:?}",
            self.write_to_files
        );

        // Configure comprehensive backtrace and panic logging
        setup_comprehensive_error_logging();

        let env_filter = build_tracing_filter(&self);

        // Debug: Print the filter string
        eprintln!(
            "TracingConfiguration::build: Tracing filter: {}",
            env_filter
        );

        let logging_ctx;
        {
            eprintln!("TracingConfiguration::build: Creating text layers");
            let (text_layers, reload_handle) = text_layers(self);
            eprintln!(
                "TracingConfiguration::build: Text layers created, reload_handle: {:?}",
                reload_handle.is_some()
            );

            // Check if tracing has already been initialized
            if tracing::dispatcher::has_been_set() {
                // If tracing is already set up, just log that we're reusing it
                eprintln!("TracingConfiguration::build: Tracing already initialized, reusing existing subscriber");
            } else {
                // Initialize tracing only if it hasn't been set up yet
                eprintln!(
                    "TracingConfiguration::build: Initializing tracing with filter: {}",
                    env_filter
                );
                match tracing_subscriber::registry()
                    .with(tracing_subscriber::EnvFilter::new(&env_filter))
                    .with(text_layers)
                    .try_init()
                {
                    Ok(_) => {
                        eprintln!("TracingConfiguration::build: Tracing initialized successfully");
                    }
                    Err(e) => {
                        eprintln!(
                            "TracingConfiguration::build: Failed to initialize tracing: {}",
                            e
                        );
                        // If initialization fails, we'll continue without tracing
                        // This prevents panics when multiple initialization attempts occur
                    }
                }
            }

            logging_ctx = LoggingCtx { reload_handle };
        }

        // Log the log levels 🧠.
        eprintln!("TracingConfiguration::build: Attempting to log setup message");
        tracing::info!(env_filter, "Logging has been set up");
        eprintln!("TracingConfiguration::build: Setup complete");
        logging_ctx
    }
}

/// Sets up comprehensive error logging including panics, backtraces, and anyhow errors
fn setup_comprehensive_error_logging() {
    // Enable full backtraces for all errors and panics
    set_var("RUST_BACKTRACE", "full");
    set_var("RUST_LIB_BACKTRACE", "1");

    // Enable colored backtraces for better readability
    #[cfg(not(target_os = "android"))]
    set_var("RUST_BACKTRACE_COLOR", "1");

    // Initialize panic logging with enhanced configuration
    log_panics::init();

    // Set up comprehensive panic hook that handles all panic types
    ErrorHandler::setup_comprehensive_panic_logging();

    // Set up tokio runtime error handling
    ErrorHandler::setup_tokio_error_handling();

    tracing::info!("Comprehensive error logging initialized");
}

fn build_tracing_filter(config: &TracingConfiguration) -> String {
    // We are intentionally not setting a global log level because we don't want to
    // risk third party crates logging sensitive information.
    // As such we need to make sure that panics will be properly logged.
    // On 2025-01-08, `log_panics` uses the `panic` target, at the error log level.
    let mut filters = vec![
        "panic=error".to_owned(),
        // Ensure all error-related targets are captured
        "anyhow=error".to_owned(),
        "error_chain=error".to_owned(),
        "failure=error".to_owned(),
        "thiserror=error".to_owned(),
        // Capture backtrace information
        "backtrace=debug".to_owned(),
        "std::backtrace=debug".to_owned(),
        // Capture tokio runtime errors
        "tokio=warn".to_owned(),
        "tokio_util=warn".to_owned(),
        "tokio::runtime=warn".to_owned(),
        "tokio::task=warn".to_owned(),
        // Capture database errors
        "diesel=warn".to_owned(),
        "rusqlite=warn".to_owned(),
        "sqlx=warn".to_owned(),
        // Capture async runtime errors
        "async_compat=warn".to_owned(),
        "futures=warn".to_owned(),
        // Capture FFI and system errors
        "libc=warn".to_owned(),
        "nix=warn".to_owned(),
        // Capture serialization errors
        "serde=warn".to_owned(),
        "serde_json=warn".to_owned(),
        // Capture network errors
        "hyper=warn".to_owned(),
        "reqwest=warn".to_owned(),
        "tower=warn".to_owned(),
        // Capture file system errors
        "walkdir=warn".to_owned(),
        "notify=warn".to_owned(),
    ];

    // Set the global log level for all targets
    let level = config.log_level;

    // Add a catch-all rule for the configured level to ensure all targets are covered
    filters.push(format!("{}", level.as_str()));

    // Also allow specific targets to be logged
    filters.push("rolling_file_appender=debug".to_owned());

    filters.join(",")
}

/// Sets up logs and the tokio runtime for the current application.
///
/// If `use_lightweight_tokio_runtime` is set to true, this will set up a
/// lightweight tokio runtime, for processes that have memory limitations (like
/// the NSE process on iOS). Otherwise, this can remain false, in which case a
/// multithreaded tokio runtime will be set up.
pub fn init_platform(
    config: TracingConfiguration,
    use_lightweight_tokio_runtime: bool,
) -> Result<(), String> {
    eprintln!("init_platform: Starting platform initialization");
    eprintln!(
        "init_platform: Use lightweight tokio runtime: {}",
        use_lightweight_tokio_runtime
    );

    {
        // Check if logging has already been initialized
        if LOGGING.get().is_some() {
            eprintln!("init_platform: Platform already initialized, skipping re-initialization");
            tracing::warn!("Platform already initialized, skipping re-initialization");
            return Ok(());
        }

        eprintln!("init_platform: Building logging configuration");
        let logging_ctx = config.build();
        eprintln!("init_platform: Logging configuration built successfully");

        LOGGING.set(logging_ctx).map_err(|_| {
            eprintln!("init_platform: Failed to set LOGGING context - already initialized");
            "logger already initialized".to_string()
        })?;

        eprintln!("init_platform: Setting up tokio runtime");
        if use_lightweight_tokio_runtime {
            eprintln!("init_platform: Setting up lightweight tokio runtime");
            setup_lightweight_tokio_runtime();
        } else {
            eprintln!("init_platform: Setting up multithreaded tokio runtime");
            setup_multithreaded_tokio_runtime();
        }
    }

    eprintln!("init_platform: Platform initialization completed successfully");
    Ok(())
}

/// Updates the tracing subscriber with a new file writer based on the provided
/// configuration.
///
/// This method will throw if `init_platform` hasn't been called, or if it was
/// called with `write_to_files` set to `None`.
pub fn reload_tracing_file_writer(configuration: TracingFileConfiguration) -> Result<(), String> {
    eprintln!(
        "reload_tracing_file_writer: Starting reload with path: {}",
        configuration.path
    );

    let Some(logging_context) = LOGGING.get() else {
        eprintln!("reload_tracing_file_writer: Logging hasn't been initialized yet");
        return Err("Logging hasn't been initialized yet".to_owned());
    };

    let Some(reload_handle) = logging_context.reload_handle.as_ref() else {
        eprintln!("reload_tracing_file_writer: Logging wasn't initialized with a file config");
        return Err("Logging wasn't initialized with a file config".to_owned());
    };

    eprintln!("reload_tracing_file_writer: Creating new file layer");
    let layer = make_file_layer(configuration);

    match layer {
        Ok(layer) => {
            eprintln!("reload_tracing_file_writer: File layer created successfully, reloading");
            reload_handle.reload(layer).map_err(|error| {
                eprintln!("reload_tracing_file_writer: Failed to reload: {}", error);
                format!("Failed to reload file config: {error}")
            })
        }
        Err(e) => {
            eprintln!(
                "reload_tracing_file_writer: Failed to create file layer: {}",
                e
            );
            Err(e)
        }
    }
}

#[cfg(not(target_family = "wasm"))]
fn setup_multithreaded_tokio_runtime() {
    async_compat::set_runtime_builder(Box::new(|| {
        eprintln!("spawning a multithreaded tokio runtime");

        // Get the number of available cores, but limit to reasonable number
        let num_available_cores = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(1);

        // Limit worker threads to 4 max to reduce memory and thread overhead
        // This is sufficient for most database operations
        let num_worker_threads = num_available_cores.min(4);

        // Limit blocking threads to 8 instead of default 512
        // This dramatically reduces thread count and memory usage
        let num_blocking_threads = 8;

        // Reduce stack size per thread to 1MB instead of default 2MB
        // This saves ~1MB per thread
        let thread_stack_size = 1024 * 1024; // 1MB

        let mut builder = tokio::runtime::Builder::new_multi_thread();
        builder
            .enable_all()
            .worker_threads(num_worker_threads)
            .max_blocking_threads(num_blocking_threads)
            .thread_stack_size(thread_stack_size);

        eprintln!(
            "Tokio runtime configured: {} worker threads, {} blocking threads, {}MB stack per thread",
            num_worker_threads,
            num_blocking_threads,
            thread_stack_size / (1024 * 1024)
        );

        builder
    }));
}

#[cfg(not(target_family = "wasm"))]
fn setup_lightweight_tokio_runtime() {
    async_compat::set_runtime_builder(Box::new(|| {
        eprintln!("spawning a lightweight tokio runtime");

        // Get the number of available cores through the system, if possible.
        let num_available_cores = std::thread::available_parallelism()
            .map(|n| n.get())
            .unwrap_or(1);

        // The number of worker threads will be either that or 4, whichever is smaller.
        let num_worker_threads = num_available_cores.min(4);

        // Chosen by a fair dice roll.
        let num_blocking_threads = 2;

        // 1 MiB of memory per worker thread. Should be enough for everyone™.
        let max_memory_bytes = 1024 * 1024;

        let mut builder = tokio::runtime::Builder::new_multi_thread();

        builder
            .enable_all()
            .worker_threads(num_worker_threads)
            .thread_stack_size(max_memory_bytes)
            .max_blocking_threads(num_blocking_threads);

        eprintln!(
            "Lightweight Tokio runtime configured: {} worker threads, {} blocking threads, {}MB stack per thread",
            num_worker_threads,
            num_blocking_threads,
            max_memory_bytes / (1024 * 1024)
        );

        builder
    }));
}
