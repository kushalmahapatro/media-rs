use std::ptr;

use super::{Format, Input, Output};
use ffi::*;

pub struct Iter {
    input: *mut AVInputFormat,
    output: *mut AVOutputFormat,
    step: Step,
}

enum Step {
    Input,
    Output,
    Done,
}

impl Iter {
    pub fn new() -> Self {
        Iter {
            input: ptr::null_mut(),
            output: ptr::null_mut(),
            step: Step::Input,
        }
    }
}

impl Default for Iter {
    fn default() -> Self {
        Self::new()
    }
}

impl Iterator for Iter {
    type Item = Format;

    fn next(&mut self) -> Option<<Self as Iterator>::Item> {
        unsafe {
            match self.step {
                Step::Input => {
                    #[cfg(not(ffmpeg_8_0))]
                    {
                        let ptr = av_iformat_next(self.input);

                        if ptr.is_null() && !self.input.is_null() {
                            self.step = Step::Output;

                            self.next()
                        } else {
                            self.input = ptr;

                            Some(Format::Input(Input::wrap(ptr)))
                        }
                    }
                    #[cfg(ffmpeg_8_0)]
                    {
                        // av_iformat_next was removed in FFmpeg 8.0.1
                        self.step = Step::Output;
                        self.next()
                    }
                }

                Step::Output => {
                    #[cfg(not(ffmpeg_8_0))]
                    {
                        let ptr = av_oformat_next(self.output);

                        if ptr.is_null() && !self.output.is_null() {
                            self.step = Step::Done;

                            self.next()
                        } else {
                            self.output = ptr;

                            Some(Format::Output(Output::wrap(ptr)))
                        }
                    }
                    #[cfg(ffmpeg_8_0)]
                    {
                        // av_oformat_next was removed in FFmpeg 8.0.1
                        self.step = Step::Done;
                        None
                    }
                }

                Step::Done => None,
            }
        }
    }
}
