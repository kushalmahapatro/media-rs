#!/bin/bash
# Build script for libheif (static library) for all platforms
# Supports: macOS, iOS, Android
# Dependencies: libde265 (built automatically)

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="$PROJECT_ROOT/third_party"
SOURCE_DIR="$THIRD_PARTY_DIR/sources"
INSTALL_DIR="$THIRD_PARTY_DIR/libheif_install"

# Get number of CPU cores
CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)

echo "=========================================="
echo "Building libheif (static library) for all platforms"
echo "=========================================="
echo "Project root: $PROJECT_ROOT"
echo "Install directory: $INSTALL_DIR"
echo ""

# Create directories
mkdir -p "$SOURCE_DIR"
mkdir -p "$INSTALL_DIR"

# Check for required tools
if ! command -v cmake &> /dev/null; then
    echo "Error: cmake is required but not installed."
    echo "Install it with: brew install cmake"
    exit 1
fi

# Function to build libde265 (dependency of libheif)
build_libde265() {
    local ARCH=$1
    local PLATFORM=$2
    local INSTALL_PREFIX=$3
    local CMAKE_FLAGS=$4
    
    echo "Building libde265 for $PLATFORM ($ARCH)..."
    
    cd "$SOURCE_DIR"
    
    # Download libde265 if not present
    if [ ! -d "libde265" ]; then
        echo "Downloading libde265..."
        if git clone --depth 1 --branch v1.0.15 https://github.com/strukturag/libde265.git 2>/dev/null; then
            echo "✓ Cloned libde265 from git"
        else
            echo "Git clone failed, trying tarball download..."
            curl -L https://github.com/strukturag/libde265/archive/v1.0.15.tar.gz | tar xz
            if [ -d "libde265-1.0.15" ]; then
                mv libde265-1.0.15 libde265
                echo "✓ Downloaded libde265 from tarball"
            else
                echo "Error: Failed to download libde265"
                return 1
            fi
        fi
    fi
    
    cd libde265
    
    # Clean previous build
    rm -rf build
    mkdir -p build
    cd build
    
    echo "Configuring libde265..."
    cmake .. \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DBUILD_SHARED_LIBS=OFF \
        -DENABLE_SDL=OFF \
        -DENABLE_DEC265=OFF \
        -DENABLE_ENCODER=OFF \
        $CMAKE_FLAGS
    
    echo "Building libde265..."
    make -j"$CORES"
    
    echo "Installing libde265..."
    make install
    
    echo "✓ libde265 built and installed to $INSTALL_PREFIX"
    echo ""
}

# Function to build libheif for macOS
build_macos() {
    echo "=========================================="
    echo "Building libheif for macOS (universal: arm64 + x86_64)"
    echo "=========================================="
    
    MACOS_INSTALL_DIR="$INSTALL_DIR/macos"
    mkdir -p "$MACOS_INSTALL_DIR"
    
    ARCHS=("arm64" "x86_64")
    LIB_NAMES=("libheif" "libde265")
    
    # Build for each architecture
    for ARCH in "${ARCHS[@]}"; do
        echo "Building for $ARCH..."
        
        BUILD_DIR="$THIRD_PARTY_DIR/libheif_build_macos_$ARCH"
        mkdir -p "$BUILD_DIR"
        
        # Build libde265 first
        DE265_INSTALL="$BUILD_DIR/libde265_install"
        mkdir -p "$DE265_INSTALL"
        
        CMAKE_FLAGS=""
        if [ "$ARCH" == "arm64" ]; then
            CMAKE_FLAGS="-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"
        else
            CMAKE_FLAGS="-DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"
        fi
        
        build_libde265 "$ARCH" "macOS" "$DE265_INSTALL" "$CMAKE_FLAGS"
        
        # Build libheif
        cd "$SOURCE_DIR"
        
        LIBHEIF_VERSION="1.20.2"
        if [ ! -d "libheif-$LIBHEIF_VERSION" ]; then
            echo "Downloading libheif $LIBHEIF_VERSION..."
            curl -L "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VERSION/libheif-$LIBHEIF_VERSION.tar.gz" | tar xz
        fi
        
        cd "libheif-$LIBHEIF_VERSION"
        
        # Clean previous build
        rm -rf "build_$ARCH"
        mkdir -p "build_$ARCH"
        cd "build_$ARCH"
        
        echo "Configuring libheif for macOS $ARCH..."
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DENABLE_PLUGIN_LOADING=OFF \
            -DWITH_AOM=OFF \
            -DWITH_DAV1D=OFF \
            -DWITH_RAV1E=OFF \
            -DWITH_X265=OFF \
            -DWITH_LIBDE265=ON \
            -DLIBDE265_INCLUDE_DIR="$DE265_INSTALL/include" \
            -DLIBDE265_LIBRARY="$DE265_INSTALL/lib/libde265.a" \
            -DWITH_EXAMPLES=OFF \
            -DWITH_TESTS=OFF \
            -DWITH_UNCOMPRESSED_CODEC=OFF \
            -DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="11.0" \
            -DCMAKE_C_FLAGS="-fPIC -mmacosx-version-min=11.0" \
            -DCMAKE_CXX_FLAGS="-fPIC -mmacosx-version-min=11.0" \
            $CMAKE_FLAGS
        
        echo "Building libheif..."
        # Build only the library target to avoid test linking issues
        make -j"$CORES" heif
        
        echo "Installing libheif..."
        # Install only the library component, skip tests
        # Try cmake install first, fallback to manual copy if needed
        if cmake --install . --component libheif 2>/dev/null; then
            echo "✓ Installed via cmake component"
            # Verify installation
            if [ ! -f "$BUILD_DIR/lib/libheif.a" ]; then
                # cmake component install may not create the file, try manual copy
                if [ -f "libheif/libheif.a" ]; then
                    mkdir -p "$BUILD_DIR/lib"
                    cp libheif/libheif.a "$BUILD_DIR/lib/"
                    echo "✓ Copied libheif.a manually"
                fi
            fi
        elif make install/strip 2>/dev/null; then
            echo "✓ Installed via make install/strip"
        else
            # Manual install as fallback
            mkdir -p "$BUILD_DIR/lib" "$BUILD_DIR/include/libheif"
            if [ -f "libheif/libheif.a" ]; then
                cp libheif/libheif.a "$BUILD_DIR/lib/"
            elif [ -f "../libheif/libheif.a" ]; then
                cp ../libheif/libheif.a "$BUILD_DIR/lib/"
            fi
            if [ -d "../libheif/api/libheif" ]; then
                cp -r ../libheif/api/libheif/*.h "$BUILD_DIR/include/libheif/" 2>/dev/null || true
            fi
            echo "✓ Installed manually"
        fi
        
        # Copy to architecture-specific directory
        ARCH_INSTALL="$MACOS_INSTALL_DIR/$ARCH"
        mkdir -p "$ARCH_INSTALL/lib" "$ARCH_INSTALL/include"
        cp "$BUILD_DIR/lib/libheif.a" "$ARCH_INSTALL/lib/"
        # Copy headers - check multiple possible locations
        if [ -d "$BUILD_DIR/include/libheif" ]; then
            cp -r "$BUILD_DIR/include/libheif" "$ARCH_INSTALL/include/"
        elif [ -d "../libheif/api/libheif" ]; then
            cp -r ../libheif/api/libheif "$ARCH_INSTALL/include/libheif"
        else
            echo "Warning: libheif headers not found"
        fi
        cp "$DE265_INSTALL/lib/libde265.a" "$ARCH_INSTALL/lib/"
        cp -r "$DE265_INSTALL/include/libde265" "$ARCH_INSTALL/include/" 2>/dev/null || true
        
        echo "✓ libheif built for macOS $ARCH"
        echo ""
    done
    
    # Create universal binaries
    echo "Creating universal binaries..."
    UNIVERSAL_DIR="$MACOS_INSTALL_DIR/universal"
    mkdir -p "$UNIVERSAL_DIR/lib" "$UNIVERSAL_DIR/include"
    
    for LIB_NAME in "${LIB_NAMES[@]}"; do
        if [ -f "$MACOS_INSTALL_DIR/arm64/lib/$LIB_NAME.a" ] && [ -f "$MACOS_INSTALL_DIR/x86_64/lib/$LIB_NAME.a" ]; then
            lipo -create \
                "$MACOS_INSTALL_DIR/arm64/lib/$LIB_NAME.a" \
                "$MACOS_INSTALL_DIR/x86_64/lib/$LIB_NAME.a" \
                -output "$UNIVERSAL_DIR/lib/$LIB_NAME.a"
            echo "✓ Created universal $LIB_NAME.a"
        fi
    done
    
    # Copy headers (same for both architectures)
    cp -r "$MACOS_INSTALL_DIR/arm64/include/"* "$UNIVERSAL_DIR/include/" 2>/dev/null || true
    
    # Create pkg-config file
    mkdir -p "$UNIVERSAL_DIR/lib/pkgconfig"
    cat > "$UNIVERSAL_DIR/lib/pkgconfig/libheif.pc" <<EOF
prefix=$UNIVERSAL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: 1.20.2
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
EOF
    
    echo "✓ macOS universal build complete!"
    echo "Location: $UNIVERSAL_DIR"
    echo ""
}

# Function to build libheif for iOS
build_ios() {
    echo "=========================================="
    echo "Building libheif for iOS"
    echo "=========================================="
    
    IOS_INSTALL_DIR="$INSTALL_DIR/ios"
    mkdir -p "$IOS_INSTALL_DIR"
    
    # iOS targets: device (arm64) and simulator (arm64, x86_64)
    TARGETS=(
        "arm64:iphoneos:device"
        "arm64:iphonesimulator:simulator"
        "x86_64:iphonesimulator:simulator"
    )
    
    for TARGET in "${TARGETS[@]}"; do
        # Parse TARGET string (format: "ARCH:PLATFORM:TYPE")
        ARCH=$(echo "$TARGET" | cut -d':' -f1)
        PLATFORM=$(echo "$TARGET" | cut -d':' -f2)
        TYPE=$(echo "$TARGET" | cut -d':' -f3)
        
        echo "Building for iOS $PLATFORM ($ARCH)..."
        
        SDK_PATH=$(xcrun --sdk $PLATFORM --show-sdk-path)
        MIN_VERSION="-miphoneos-version-min=16.0"
        if [ "$PLATFORM" == "iphonesimulator" ]; then
            MIN_VERSION="-mios-simulator-version-min=16.0"
        fi
        
        BUILD_DIR="$THIRD_PARTY_DIR/libheif_build_ios_${ARCH}_${TYPE}"
        mkdir -p "$BUILD_DIR"
        
        # Build libde265 first
        DE265_INSTALL="$BUILD_DIR/libde265_install"
        mkdir -p "$DE265_INSTALL"
        
        CMAKE_FLAGS="
            -DCMAKE_SYSTEM_NAME=iOS
            -DCMAKE_OSX_SYSROOT=$SDK_PATH
            -DCMAKE_OSX_ARCHITECTURES=$ARCH
            -DCMAKE_C_FLAGS=\"$MIN_VERSION\"
            -DCMAKE_CXX_FLAGS=\"$MIN_VERSION\"
        "
        
        build_libde265 "$ARCH" "iOS-$PLATFORM" "$DE265_INSTALL" "$CMAKE_FLAGS"
        
        # Build libheif
        cd "$SOURCE_DIR"
        
        LIBHEIF_VERSION="1.20.2"
        if [ ! -d "libheif-$LIBHEIF_VERSION" ]; then
            echo "Downloading libheif $LIBHEIF_VERSION..."
            curl -L "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VERSION/libheif-$LIBHEIF_VERSION.tar.gz" | tar xz
        fi
        
        cd "libheif-$LIBHEIF_VERSION"
        
        # Clean previous build
        rm -rf "build_ios_${ARCH}_${TYPE}"
        mkdir -p "build_ios_${ARCH}_${TYPE}"
        cd "build_ios_${ARCH}_${TYPE}"
        
        echo "Configuring libheif for iOS $PLATFORM $ARCH..."
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
            -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DENABLE_PLUGIN_LOADING=OFF \
            -DWITH_AOM=OFF \
            -DWITH_DAV1D=OFF \
            -DWITH_RAV1E=OFF \
            -DWITH_X265=OFF \
            -DWITH_LIBDE265=ON \
            -DLIBDE265_INCLUDE_DIR="$DE265_INSTALL/include" \
            -DLIBDE265_LIBRARY="$DE265_INSTALL/lib/libde265.a" \
            -DWITH_EXAMPLES=OFF \
            -DWITH_TESTS=OFF \
            -DWITH_UNCOMPRESSED_CODEC=OFF \
            -DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON \
            -DCMAKE_C_FLAGS="$MIN_VERSION -fPIC" \
            -DCMAKE_CXX_FLAGS="$MIN_VERSION -fPIC"
        
        echo "Building libheif..."
        # Build only the library target to avoid test linking issues
        make -j"$CORES" heif
        
        echo "Installing libheif..."
        # Install only the library component, skip tests
        # Try cmake install first, fallback to manual copy if needed
        if cmake --install . --component libheif 2>/dev/null; then
            echo "✓ Installed via cmake component"
            # Verify installation
            if [ ! -f "$BUILD_DIR/lib/libheif.a" ]; then
                # cmake component install may not create the file, try manual copy
                if [ -f "libheif/libheif.a" ]; then
                    mkdir -p "$BUILD_DIR/lib"
                    cp libheif/libheif.a "$BUILD_DIR/lib/"
                    echo "✓ Copied libheif.a manually"
                fi
            fi
        elif make install/strip 2>/dev/null; then
            echo "✓ Installed via make install/strip"
        else
            # Manual install as fallback
            mkdir -p "$BUILD_DIR/lib" "$BUILD_DIR/include/libheif"
            if [ -f "libheif/libheif.a" ]; then
                cp libheif/libheif.a "$BUILD_DIR/lib/"
            elif [ -f "../libheif/libheif.a" ]; then
                cp ../libheif/libheif.a "$BUILD_DIR/lib/"
            fi
            if [ -d "../libheif/api/libheif" ]; then
                cp -r ../libheif/api/libheif/*.h "$BUILD_DIR/include/libheif/" 2>/dev/null || true
            fi
            echo "✓ Installed manually"
        fi
        
        # Copy to platform-specific directory
        PLATFORM_INSTALL="$IOS_INSTALL_DIR/$PLATFORM/$ARCH"
        mkdir -p "$PLATFORM_INSTALL/lib" "$PLATFORM_INSTALL/include"
        cp "$BUILD_DIR/lib/libheif.a" "$PLATFORM_INSTALL/lib/"
        cp -r "$BUILD_DIR/include/libheif" "$PLATFORM_INSTALL/include/"
        cp "$DE265_INSTALL/lib/libde265.a" "$PLATFORM_INSTALL/lib/"
        cp -r "$DE265_INSTALL/include/libde265" "$PLATFORM_INSTALL/include/" 2>/dev/null || true
        
        # Create pkg-config file for iOS
        mkdir -p "$PLATFORM_INSTALL/lib/pkgconfig"
        cat > "$PLATFORM_INSTALL/lib/pkgconfig/libheif.pc" <<EOF
prefix=$PLATFORM_INSTALL
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: 1.20.2
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
EOF
        
        echo "✓ libheif built for iOS $PLATFORM $ARCH"
        echo ""
    done
    
    echo "✓ iOS build complete!"
    echo "Location: $IOS_INSTALL_DIR"
    echo ""
}

# Function to build libheif for Android
build_android() {
    echo "=========================================="
    echo "Building libheif for Android"
    echo "=========================================="
    
    if [ -z "$ANDROID_NDK_HOME" ]; then
        echo "Error: ANDROID_NDK_HOME is not set."
        echo "Please set it to your Android NDK location (e.g., export ANDROID_NDK_HOME=\$HOME/Library/Android/sdk/ndk/27.something)"
        exit 1
    fi
    
    ANDROID_INSTALL_DIR="$INSTALL_DIR/android"
    mkdir -p "$ANDROID_INSTALL_DIR"
    
    # Android ABIs
    ABIS=("arm64-v8a" "x86_64")
    API_LEVEL=21
    
    # Detect host tag for NDK toolchain
    HOST_OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" == "arm64" ] || [ "$HOST_ARCH" == "aarch64" ]; then
        HOST_TAG="darwin-arm64"
    else
        HOST_TAG="darwin-x86_64"
    fi
    
    TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
    if [ ! -d "$TOOLCHAIN" ]; then
        # Fallback to darwin-x86_64 on Apple Silicon (runs via Rosetta)
        if [ "$HOST_TAG" == "darwin-arm64" ]; then
            HOST_TAG="darwin-x86_64"
            TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
        fi
    fi
    
    if [ ! -d "$TOOLCHAIN" ]; then
        echo "Error: Could not find NDK toolchain at $TOOLCHAIN"
        echo "Available toolchains:"
        ls -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/"* 2>/dev/null || echo "  (none found)"
        exit 1
    fi
    
    echo "Using NDK toolchain: $TOOLCHAIN"
    
    for ABI in "${ABIS[@]}"; do
        echo "Building for Android $ABI..."
        
        BUILD_DIR="$THIRD_PARTY_DIR/libheif_build_android_$ABI"
        mkdir -p "$BUILD_DIR"
        
        # Set up Android toolchain variables
        case $ABI in
            arm64-v8a)
                ARCH="aarch64"
                TRIPLE="aarch64-linux-android"
                CC="$TOOLCHAIN/bin/aarch64-linux-android$API_LEVEL-clang"
                CXX="$TOOLCHAIN/bin/aarch64-linux-android$API_LEVEL-clang++"
                ;;
            x86_64)
                ARCH="x86_64"
                TRIPLE="x86_64-linux-android"
                CC="$TOOLCHAIN/bin/x86_64-linux-android$API_LEVEL-clang"
                CXX="$TOOLCHAIN/bin/x86_64-linux-android$API_LEVEL-clang++"
                ;;
        esac
        
        SYSROOT="$TOOLCHAIN/sysroot"
        
        # Build libde265 first
        DE265_INSTALL="$BUILD_DIR/libde265_install"
        mkdir -p "$DE265_INSTALL"
        
        cd "$SOURCE_DIR"
        if [ ! -d "libde265" ]; then
            echo "Downloading libde265..."
            if git clone --depth 1 --branch v1.0.15 https://github.com/strukturag/libde265.git 2>/dev/null; then
                echo "✓ Cloned libde265 from git"
            else
                echo "Git clone failed, trying tarball download..."
                curl -L https://github.com/strukturag/libde265/archive/v1.0.15.tar.gz | tar xz
                if [ -d "libde265-1.0.15" ]; then
                    mv libde265-1.0.15 libde265
                    echo "✓ Downloaded libde265 from tarball"
                else
                    echo "Error: Failed to download libde265"
                    return 1
                fi
            fi
        fi
        
        cd libde265
        rm -rf "build_android_$ABI"
        mkdir -p "build_android_$ABI"
        cd "build_android_$ABI"
        
        echo "Configuring libde265 for Android $ABI..."
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$DE265_INSTALL" \
            -DCMAKE_SYSTEM_NAME=Android \
            -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
            -DCMAKE_ANDROID_ARCH_ABI="$ABI" \
            -DCMAKE_ANDROID_NDK="$ANDROID_NDK_HOME" \
            -DCMAKE_ANDROID_STL_TYPE=c++_static \
            -DCMAKE_C_COMPILER="$CC" \
            -DCMAKE_CXX_COMPILER="$CXX" \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
            -DBUILD_SHARED_LIBS=OFF \
            -DENABLE_SDL=OFF \
            -DENABLE_DEC265=OFF \
            -DENABLE_ENCODER=OFF \
            -DCMAKE_C_FLAGS="--sysroot=$SYSROOT -fPIC" \
            -DCMAKE_CXX_FLAGS="--sysroot=$SYSROOT -fPIC"
        
        echo "Building libde265..."
        make -j"$CORES"
        
        echo "Installing libde265..."
        make install
        
        # Build libheif
        cd "$SOURCE_DIR"
        
        LIBHEIF_VERSION="1.20.2"
        if [ ! -d "libheif-$LIBHEIF_VERSION" ]; then
            echo "Downloading libheif $LIBHEIF_VERSION..."
            curl -L "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VERSION/libheif-$LIBHEIF_VERSION.tar.gz" | tar xz
        fi
        
        cd "libheif-$LIBHEIF_VERSION"
        
        rm -rf "build_android_$ABI"
        mkdir -p "build_android_$ABI"
        cd "build_android_$ABI"
        
        echo "Configuring libheif for Android $ABI..."
        cmake .. \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
            -DCMAKE_SYSTEM_NAME=Android \
            -DCMAKE_SYSTEM_PROCESSOR="$ARCH" \
            -DCMAKE_ANDROID_ARCH_ABI="$ABI" \
            -DCMAKE_ANDROID_NDK="$ANDROID_NDK_HOME" \
            -DCMAKE_ANDROID_STL_TYPE=c++_static \
            -DCMAKE_C_COMPILER="$CC" \
            -DCMAKE_CXX_COMPILER="$CXX" \
            -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
            -DBUILD_SHARED_LIBS=OFF \
            -DENABLE_PLUGIN_LOADING=OFF \
            -DWITH_AOM=OFF \
            -DWITH_DAV1D=OFF \
            -DWITH_RAV1E=OFF \
            -DWITH_X265=OFF \
            -DWITH_LIBDE265=ON \
            -DLIBDE265_INCLUDE_DIR="$DE265_INSTALL/include" \
            -DLIBDE265_LIBRARY="$DE265_INSTALL/lib/libde265.a" \
            -DWITH_EXAMPLES=OFF \
            -DWITH_TESTS=OFF \
            -DWITH_UNCOMPRESSED_CODEC=OFF \
            -DCMAKE_DISABLE_FIND_PACKAGE_AOM=ON \
            -DCMAKE_DISABLE_FIND_PACKAGE_libsharpyuv=ON \
            -DCMAKE_C_FLAGS="--sysroot=$SYSROOT -fPIC" \
            -DCMAKE_CXX_FLAGS="--sysroot=$SYSROOT -fPIC"
        
        echo "Building libheif..."
        # Build only the library target to avoid test linking issues
        make -j"$CORES" heif
        
        echo "Installing libheif..."
        # Install only the library component, skip tests
        # Try cmake install first, fallback to manual copy if needed
        if cmake --install . --component libheif 2>/dev/null; then
            echo "✓ Installed via cmake component"
            # Verify installation
            if [ ! -f "$BUILD_DIR/lib/libheif.a" ]; then
                # cmake component install may not create the file, try manual copy
                if [ -f "libheif/libheif.a" ]; then
                    mkdir -p "$BUILD_DIR/lib"
                    cp libheif/libheif.a "$BUILD_DIR/lib/"
                    echo "✓ Copied libheif.a manually"
                fi
            fi
        elif make install/strip 2>/dev/null; then
            echo "✓ Installed via make install/strip"
        else
            # Manual install as fallback
            mkdir -p "$BUILD_DIR/lib" "$BUILD_DIR/include/libheif"
            if [ -f "libheif/libheif.a" ]; then
                cp libheif/libheif.a "$BUILD_DIR/lib/"
            elif [ -f "../libheif/libheif.a" ]; then
                cp ../libheif/libheif.a "$BUILD_DIR/lib/"
            fi
            if [ -d "../libheif/api/libheif" ]; then
                cp -r ../libheif/api/libheif/*.h "$BUILD_DIR/include/libheif/" 2>/dev/null || true
            fi
            echo "✓ Installed manually"
        fi
        
        # Copy to ABI-specific directory
        ABI_INSTALL="$ANDROID_INSTALL_DIR/$ABI"
        mkdir -p "$ABI_INSTALL/lib" "$ABI_INSTALL/include"
        
        # Find and copy libheif.a (cmake install may place it in different locations)
        if [ -f "$BUILD_DIR/lib/libheif.a" ]; then
            cp "$BUILD_DIR/lib/libheif.a" "$ABI_INSTALL/lib/"
        else
            # Try to find it in the build directory
            FOUND_LIB=$(find "$BUILD_DIR" -name "libheif.a" -type f 2>/dev/null | head -1)
            if [ -n "$FOUND_LIB" ]; then
                cp "$FOUND_LIB" "$ABI_INSTALL/lib/"
            else
                echo "Warning: libheif.a not found in $BUILD_DIR"
            fi
        fi
        
        # Copy headers
        if [ -d "$BUILD_DIR/include/libheif" ]; then
            cp -r "$BUILD_DIR/include/libheif" "$ABI_INSTALL/include/"
        else
            # Try to find headers
            FOUND_INCLUDE=$(find "$BUILD_DIR" -type d -name "libheif" -path "*/include/*" 2>/dev/null | head -1)
            if [ -n "$FOUND_INCLUDE" ]; then
                cp -r "$FOUND_INCLUDE" "$ABI_INSTALL/include/"
            fi
        fi
        
        # Copy libde265
        if [ -f "$DE265_INSTALL/lib/libde265.a" ]; then
            cp "$DE265_INSTALL/lib/libde265.a" "$ABI_INSTALL/lib/"
        fi
        if [ -d "$DE265_INSTALL/include/libde265" ]; then
            cp -r "$DE265_INSTALL/include/libde265" "$ABI_INSTALL/include/" 2>/dev/null || true
        elif [ -d "$DE265_INSTALL/include" ]; then
            cp -r "$DE265_INSTALL/include/"* "$ABI_INSTALL/include/" 2>/dev/null || true
        fi
        
        # Create pkg-config file
        mkdir -p "$ABI_INSTALL/lib/pkgconfig"
        cat > "$ABI_INSTALL/lib/pkgconfig/libheif.pc" <<EOF
prefix=$ABI_INSTALL
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: libheif
Description: HEIF image codec library
Version: 1.20.2
Libs: -L\${libdir} -lheif -lde265
Cflags: -I\${includedir}
Requires:
EOF
        
        echo "✓ libheif built for Android $ABI"
        echo ""
    done
    
    echo "✓ Android build complete!"
    echo "Location: $ANDROID_INSTALL_DIR"
    echo ""
}

# Main execution
if [ "$1" == "--macos-only" ]; then
    build_macos
elif [ "$1" == "--ios-only" ]; then
    build_ios
elif [ "$1" == "--android-only" ]; then
    build_android
else
    # Build for all platforms
    build_macos
    build_ios
    build_android
fi

echo "=========================================="
echo "libheif build complete for all platforms!"
echo "=========================================="
echo "Installation locations:"
echo "  macOS: $INSTALL_DIR/macos/universal"
echo "  iOS: $INSTALL_DIR/ios"
echo "  Android: $INSTALL_DIR/android"
echo ""
echo "Static libraries:"
echo "  - libheif.a (HEIF codec)"
echo "  - libde265.a (HEVC decoder, dependency)"
echo ""

