use std::{fs, io};

use anyhow::Error;
use logging::platform::{TracingConfiguration, TracingFileConfiguration};

pub use logging::tracing::LogLevel;

pub async fn log(
    file: String,
    line: Option<u32>,
    level: LogLevel,
    target: String,
    message: String,
) {
    logging::tracing::log_event(file, line, level, target, message);
}

pub struct WriteToFiles {
    pub path: String,
    pub file_prefix: String,
    pub file_suffix: Option<String>,
    pub max_files: Option<u64>,
}

#[allow(unexpected_cfgs)]
pub enum _LogLevel {
    Error,
    Warn,
    Info,
    Debug,
    Trace,
}

pub fn debug_threads() -> io::Result<()> {
    // current process id
    let pid = std::process::id();
    let task_dir = format!("/proc/{}/task", pid);

    for entry in fs::read_dir(task_dir)? {
        let tid = entry?.file_name().into_string().unwrap();
        let comm_path = format!("/proc/{}/task/{}/comm", pid, tid);

        if let Ok(name) = fs::read_to_string(&comm_path) {
            println!("TID {} => {}", tid, name.trim());
        }
    }
    Ok(())
}

pub async fn init_logger(
    log_level: LogLevel,
    write_to_stdout_or_system: bool,
    write_to_files: Option<WriteToFiles>,
    use_lightweight_tokio_runtime: bool,
) -> Result<(), Error> {
    let file_config = match write_to_files {
        Some(files) => Some(TracingFileConfiguration {
            path: files.path,
            file_prefix: files.file_prefix,
            file_suffix: files.file_suffix,
            max_files: files.max_files,
        }),
        None => None,
    };

    let config = TracingConfiguration {
        log_level,
        write_to_stdout_or_system,
        write_to_files: file_config,
    };

    logging::platform::init_platform(config, use_lightweight_tokio_runtime)
        .map_err(Error::msg)
}

pub async fn reload_tracing_file_writer(write_to_files: WriteToFiles) -> Result<(), Error> {
    let file_config = TracingFileConfiguration {
        path: write_to_files.path,
        file_prefix: write_to_files.file_prefix,
        file_suffix: write_to_files.file_suffix,
        max_files: write_to_files.max_files,
    };

    logging::platform::reload_tracing_file_writer(file_config).map_err(Error::msg)
}