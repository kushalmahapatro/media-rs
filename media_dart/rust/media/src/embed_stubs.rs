//! Collecting StreamSink when `media` is embedded in another FRB cdylib (Connect bridge).
//! Progress / frame APIs still call `add`; hosts read results via [`StreamSink::take_items`].

use std::marker::PhantomData;
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub struct StreamSink<T> {
    items: Arc<Mutex<Vec<T>>>,
    _item: PhantomData<T>,
}

impl<T> StreamSink<T> {
    pub fn new() -> Self {
        Self {
            items: Arc::new(Mutex::new(Vec::new())),
            _item: PhantomData,
        }
    }

    pub fn add(&self, item: T) {
        if let Ok(mut guard) = self.items.lock() {
            guard.push(item);
        }
    }

    pub fn take_items(&self) -> Vec<T> {
        self.items
            .lock()
            .map(|mut guard| std::mem::take(&mut *guard))
            .unwrap_or_default()
    }
}

impl<T> Default for StreamSink<T> {
    fn default() -> Self {
        Self::new()
    }
}
