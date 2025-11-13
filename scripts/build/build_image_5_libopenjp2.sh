#!/bin/bash
set -e

# Source common build functionality (platform detection, paths, interactive mode, colors, helpers)
# This allows the script to be run standalone. When called from 2_build.sh,
# variables are already exported, but sourcing again is harmless.
source "$(dirname "$0")/_build_common.sh" "$@"

LIBRARY_NAME="libopenjp2"
ARCHIVE_NAME="libopenjp2.tar.gz"

print_header "Starting ${LIBRARY_NAME} Build"

# Clean and create output directories (ensures they exist and are empty)
interactive_prompt \
    "Ready to clean and create output directories for ${LIBRARY_NAME}" \
    "Will remove and recreate: ${OUTPUT_INCLUDE}/${LIBRARY_NAME}" \
    "Will remove and recreate: ${OUTPUT_LIB}/${LIBRARY_NAME}" \
    "Will remove and recreate: ${OUTPUT_SRC}/${LIBRARY_NAME}"

rm -rf "${OUTPUT_INCLUDE}/${LIBRARY_NAME}"
rm -rf "${OUTPUT_LIB}/${LIBRARY_NAME}"
rm -rf "${OUTPUT_SRC}/${LIBRARY_NAME}"

mkdir -p "${OUTPUT_INCLUDE}/${LIBRARY_NAME}"
mkdir -p "${OUTPUT_LIB}/${LIBRARY_NAME}"
mkdir -p "${OUTPUT_SRC}/${LIBRARY_NAME}"

# Extract source to output/platforms/${PLATFORM}/src/
interactive_prompt \
    "Ready to extract source archive" \
    "Archive: ${SOURCE_ARCHIVES}/${ARCHIVE_NAME}" \
    "Destination: ${OUTPUT_SRC}/${LIBRARY_NAME}"

cd "${OUTPUT_SRC}/${LIBRARY_NAME}"
tar -xf "${SOURCE_ARCHIVES}/${ARCHIVE_NAME}" --strip-components=1

# Create build directory
BUILD_DIR="${OUTPUT_SRC}/${LIBRARY_NAME}/_build"
mkdir -p "${BUILD_DIR}"
PREFIX="${BUILD_DIR}"

# Configure and build
interactive_prompt \
    "Ready to configure and build ${LIBRARY_NAME}" \
    "Platform: ${PLATFORM}" \
    "Build directory: ${BUILD_DIR}"

if [[ $OS = 'Darwin' ]]; then
    # macOS universal build
    print_info "Configuring for macOS (universal: arm64 + x86_64)..."
    CFLAGS="-arch arm64 -arch x86_64 -mmacosx-version-min=10.15" \
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RELEASE -DBUILD_SHARED_LIBS:BOOL=OFF \
        -DCMAKE_IGNORE_PATH=/usr/local/lib/ \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_LIBRARY_PATH:path="${OUTPUT_LIB}" -DCMAKE_INCLUDE_PATH:path="${OUTPUT_INCLUDE}" \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" ./
    
elif [[ $OS = 'Linux' ]]; then
    # Linux build
    print_info "Configuring for Linux..."
    # Locally, webp isn't detected and build succeeds. On GitHub runners, pkg-config
    # finds webp.pc but the library files aren't available, causing linker errors.
    CC=clang CXX=clang++ \
    CFLAGS="-fPIC" \
    cmake -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=RELEASE -DBUILD_SHARED_LIBS:BOOL=OFF \
        -DCMAKE_IGNORE_PATH=/usr/lib/x86_64-linux-gnu/ \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_LIBRARY_PATH:path="${OUTPUT_LIB}" -DCMAKE_INCLUDE_PATH:path="${OUTPUT_INCLUDE}" \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_DISABLE_FIND_PACKAGE_WebP:BOOL=ON \
        -DCMAKE_VERBOSE_MAKEFILE:BOOL=ON \
        -DCMAKE_EXE_LINKER_FLAGS="-Wl,--verbose" \
        ./
    
    # Diagnostic: Check if webp was detected
    cd "${BUILD_DIR}"
    print_info "Checking if webp was detected by CMake..."
    if grep -q "WEBP" CMakeCache.txt 2>/dev/null; then
        print_info "WebP-related variables found in CMakeCache.txt:"
        grep -i "WEBP" CMakeCache.txt | head -10 || true
    else
        print_info "No WebP variables found in CMakeCache.txt"
    fi
    
    # Check linker commands in generated Makefiles
    print_info "Checking linker commands for -lwebp..."
    LINK_FILES=$(find . -name "link.txt" -type f 2>/dev/null | head -3)
    if [[ -n "$LINK_FILES" ]]; then
        for link_file in $LINK_FILES; do
            if grep -q "-lwebp" "$link_file" 2>/dev/null; then
                print_info "Found -lwebp in: $link_file"
                grep "-lwebp" "$link_file" || true
            else
                print_info "No -lwebp found in: $link_file"
            fi
        done
    fi
    
    # Remove -lwebp from linker flags if CMake detected it
    # This handles the case where pkg-config finds webp.pc but library files don't exist
    if grep -q "WEBP_LIBRARIES" CMakeCache.txt 2>/dev/null || grep -rq "-lwebp" . --include="*.make" --include="link.txt" 2>/dev/null; then
        print_info "Removing webp from linker flags..."
        sed -i 's/-lwebp//g' CMakeCache.txt 2>/dev/null || true
        sed -i 's/;-lwebp//g' CMakeCache.txt 2>/dev/null || true
        # Also update the generated Makefiles
        find . -name "*.make" -type f -exec sed -i 's/-lwebp//g' {} \; 2>/dev/null || true
        find . -name "link.txt" -type f -exec sed -i 's/-lwebp//g' {} \; 2>/dev/null || true
        print_info "Removed -lwebp from linker flags"
    else
        print_info "No -lwebp found to remove (webp not detected)"
    fi
    cd "${OUTPUT_SRC}/${LIBRARY_NAME}"
fi

print_info "Building ${LIBRARY_NAME} (${JOBS} parallel jobs)..."
make -j${JOBS}
make install

# Copy headers and libraries
interactive_prompt \
    "Ready to copy headers and libraries" \
    "Headers: ${OUTPUT_INCLUDE}/${LIBRARY_NAME}/" \
    "Library: ${OUTPUT_LIB}/${LIBRARY_NAME}/${LIBRARY_NAME}.a"

cp -R "${PREFIX}/include/openjpeg-2.5"/* "${OUTPUT_INCLUDE}/${LIBRARY_NAME}/" 2>/dev/null || true
cp "${PREFIX}/lib/${LIBRARY_NAME}.a" "${OUTPUT_LIB}/${LIBRARY_NAME}/"

print_success "Build complete for ${LIBRARY_NAME}"
