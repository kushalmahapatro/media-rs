#!/bin/bash

brew install ffmpeg@8

export FFMPEG_DIR="$(brew --prefix ffmpeg)"
export FFMPEG_INCLUDE_DIR="$FFMPEG_DIR/include"
export FFMPEG_PKG_CONFIG_PATH="$FFMPEG_DIR/lib/pkgconfig"
export PKG_CONFIG_PATH="$FFMPEG_PKG_CONFIG_PATH:$PKG_CONFIG_PATH"