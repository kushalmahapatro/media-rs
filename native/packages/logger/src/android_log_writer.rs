//! Android logcat writer for `tracing-subscriber::fmt`, compatible with the workspace
//! `tracing-subscriber` revision. Adapted from the MIT-licensed `paranoid-android` crate
//! (https://github.com/element-hq/paranoid-android) to avoid a second `tracing-subscriber` in the graph.

use core::slice;
use std::{
    ffi::{CStr, CString},
    io::{self, Write},
    os::raw::c_char,
};

use lazy_static::lazy_static;
use ndk_sys::{android_LogPriority, log_id, __android_log_buf_write};
use sharded_slab::{pool::RefMut, Pool};
use smallvec::SmallVec;
use tracing_core::Metadata;
use tracing_subscriber::fmt::writer::MakeWriter;

#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
#[allow(dead_code)] // Fatal reserved for parity with Android priorities
enum Priority {
    Verbose = android_LogPriority::ANDROID_LOG_VERBOSE.0,
    Debug = android_LogPriority::ANDROID_LOG_DEBUG.0,
    Info = android_LogPriority::ANDROID_LOG_INFO.0,
    Warn = android_LogPriority::ANDROID_LOG_WARN.0,
    Error = android_LogPriority::ANDROID_LOG_ERROR.0,
    Fatal = android_LogPriority::ANDROID_LOG_FATAL.0,
}

#[repr(u32)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[allow(dead_code)] // Only Default used; others kept for future buffer selection
enum Buffer {
    Default = log_id::LOG_ID_DEFAULT.0,
    Main = log_id::LOG_ID_MAIN.0,
    Crash = log_id::LOG_ID_CRASH.0,
    Stats = log_id::LOG_ID_STATS.0,
    Events = log_id::LOG_ID_EVENTS.0,
    Security = log_id::LOG_ID_SECURITY.0,
    System = log_id::LOG_ID_SYSTEM.0,
    Kernel = log_id::LOG_ID_KERNEL.0,
    Radio = log_id::LOG_ID_RADIO.0,
}

impl Priority {
    fn as_raw(self) -> android_LogPriority {
        android_LogPriority(self as u32)
    }
}

impl From<tracing_core::Level> for Priority {
    fn from(l: tracing_core::Level) -> Self {
        match l {
            tracing_core::Level::TRACE => Priority::Verbose,
            tracing_core::Level::DEBUG => Priority::Debug,
            tracing_core::Level::INFO => Priority::Info,
            tracing_core::Level::WARN => Priority::Warn,
            tracing_core::Level::ERROR => Priority::Error,
        }
    }
}

impl Buffer {
    fn as_raw(self) -> log_id {
        log_id(self as u32)
    }
}

impl Default for Buffer {
    fn default() -> Self {
        Self::Default
    }
}

/// The writer produced by [`AndroidLogMakeWriter`].
#[derive(Debug)]
pub struct AndroidLogWriter<'a> {
    tag: &'a CStr,
    message: PooledCString,
    priority: Priority,
    buffer: Buffer,
}

/// A [`MakeWriter`] suitable for writing Android logs.
#[derive(Debug)]
pub struct AndroidLogMakeWriter {
    tag: CString,
    buffer: Buffer,
}

const MAX_LOG_LEN: usize = 4000;

impl Write for AndroidLogWriter<'_> {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.message.write(buf);
        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        let mut sv = SmallVec::<[PooledCString; 4]>::new();
        let messages = if self.message.as_bytes().len() < MAX_LOG_LEN {
            MessageIter::Single(Some(&mut self.message))
        } else {
            sv.extend(
                self.message
                    .as_bytes()
                    .chunks(MAX_LOG_LEN)
                    .map(PooledCString::new),
            );
            MessageIter::Multi(sv.as_mut().iter_mut())
        }
        .filter_map(PooledCString::as_ptr);

        let buffer = self.buffer.as_raw().0 as i32;
        let priority = self.priority.as_raw().0 as i32;
        let tag = self.tag.as_ptr();

        for message in messages {
            unsafe { __android_log_buf_write(buffer, priority, tag, message) };
        }

        Ok(())
    }
}

impl Drop for AndroidLogWriter<'_> {
    fn drop(&mut self) {
        let _ = self.flush();
    }
}

impl<'a> MakeWriter<'a> for AndroidLogMakeWriter {
    type Writer = AndroidLogWriter<'a>;

    fn make_writer(&'a self) -> Self::Writer {
        AndroidLogWriter {
            tag: self.tag.as_c_str(),
            message: PooledCString::empty(),
            buffer: self.buffer,
            priority: Priority::Info,
        }
    }

    fn make_writer_for(&'a self, meta: &Metadata<'_>) -> Self::Writer {
        let priority = (*meta.level()).into();

        AndroidLogWriter {
            tag: self.tag.as_c_str(),
            message: PooledCString::empty(),
            buffer: self.buffer,
            priority,
        }
    }
}

impl AndroidLogMakeWriter {
    pub fn new(tag: String) -> Self {
        Self {
            tag: CString::new(tag).expect("log tag must not contain NUL"),
            buffer: Buffer::default(),
        }
    }
}

#[derive(Debug)]
struct PooledCString {
    buf: RefMut<'static, Vec<u8>>,
}

enum MessageIter<'a> {
    Single(Option<&'a mut PooledCString>),
    Multi(slice::IterMut<'a, PooledCString>),
}

lazy_static! {
    static ref BUFFER_POOL: Pool<Vec<u8>> = Pool::new();
}

impl PooledCString {
    fn empty() -> Self {
        Self {
            buf: BUFFER_POOL.create().expect("buffer pool"),
        }
    }

    fn new(data: &[u8]) -> Self {
        let mut this = PooledCString::empty();
        this.write(data);
        this
    }

    fn write(&mut self, data: &[u8]) {
        self.buf.extend_from_slice(data);
    }

    fn as_ptr(&mut self) -> Option<*const c_char> {
        if self.buf.last().copied() != Some(0) {
            self.buf.push(0);
        }

        CStr::from_bytes_with_nul(self.buf.as_ref())
            .ok()
            .map(CStr::as_ptr)
    }

    fn as_bytes(&self) -> &[u8] {
        self.buf.as_ref()
    }
}

impl Drop for PooledCString {
    fn drop(&mut self) {
        BUFFER_POOL.clear(self.buf.key());
    }
}

impl<'a> Iterator for MessageIter<'a> {
    type Item = &'a mut PooledCString;

    fn next(&mut self) -> Option<Self::Item> {
        match self {
            MessageIter::Single(message) => message.take(),
            MessageIter::Multi(iter) => iter.next(),
        }
    }

    fn size_hint(&self) -> (usize, Option<usize>) {
        match self {
            MessageIter::Single(Some(_)) => (1, Some(1)),
            MessageIter::Single(None) => (0, Some(0)),
            MessageIter::Multi(iter) => iter.size_hint(),
        }
    }
}
