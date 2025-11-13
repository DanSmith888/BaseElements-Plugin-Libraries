#!/bin/bash
# Script to compare installed packages between local VM and GitHub Actions runners
# This helps identify why ImageMagick configure detects different optional libraries

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

print_info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}WARNING:${NC} $1"
}

print_error() {
    echo -e "${RED}ERROR:${NC} $1"
}

# Detect OS
OS=$(uname -s)
if [[ "$OS" != "Linux" ]]; then
    print_error "This script is designed for Linux systems"
    exit 1
fi

# Detect Ubuntu version
if [[ ! -r /etc/os-release ]]; then
    print_error "Cannot read /etc/os-release"
    exit 1
fi

UBUNTU_VERSION=$(grep VERSION_ID /etc/os-release | cut -d'"' -f2)
# Use HOSTNAME env var if set (for GitHub Actions), otherwise use hostname command
HOSTNAME="${HOSTNAME:-$(hostname)}"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="package_list_${HOSTNAME}_${UBUNTU_VERSION}_${TIMESTAMP}.txt"

print_header "Package Comparison Tool"
echo ""
print_info "Hostname: ${HOSTNAME}"
print_info "Ubuntu Version: ${UBUNTU_VERSION}"
print_info "Output file: ${OUTPUT_FILE}"
echo ""

# Create output directory if it doesn't exist
mkdir -p package_lists

OUTPUT_PATH="package_lists/${OUTPUT_FILE}"

print_header "Collecting Package Information"

# 1. All installed packages (detailed)
print_info "Listing all installed packages (detailed)..."
dpkg -l > "${OUTPUT_PATH}.dpkg_full"

# 1b. All installed packages (package names only, sorted)
print_info "Listing all installed packages (names only)..."
dpkg -l | grep '^ii' | awk '{print $2}' | sort > "${OUTPUT_PATH}.all"

# 2. ImageMagick-related packages (the ones that matter)
print_info "Checking for ImageMagick-related packages..."
IMAGEMAGICK_PACKAGES=(
    "liblcms2"
    "liblqr"
    "libdjvulibre"
    "libopenexr"
    "libjbig"
    "libtiff"
    "libopenjp2"
    "imagemagick"
    "libmagick"
    "libheif"
    "libde265"
    "libturbojpeg"
    "libpng"
    "libjpeg"
    "libfreetype"
    "libfontconfig"
)

echo "" >> "${OUTPUT_PATH}"
echo "=== ImageMagick Related Packages ===" >> "${OUTPUT_PATH}"
for pkg_pattern in "${IMAGEMAGICK_PACKAGES[@]}"; do
    dpkg -l | grep -i "$pkg_pattern" | grep '^ii' >> "${OUTPUT_PATH}" || true
done

# 3. Development packages (dev packages often provide headers that configure detects)
print_info "Listing development packages..."
echo "" >> "${OUTPUT_PATH}"
echo "=== Development Packages (-dev packages) ===" >> "${OUTPUT_PATH}"
dpkg -l | grep '^ii' | grep '\-dev' | awk '{print $2}' | sort >> "${OUTPUT_PATH}"

# 4. pkg-config files that might affect ImageMagick
print_info "Checking pkg-config files..."
echo "" >> "${OUTPUT_PATH}"
echo "=== pkg-config files in /usr/lib/pkgconfig ===" >> "${OUTPUT_PATH}"
if [[ -d /usr/lib/pkgconfig ]]; then
    find /usr/lib/pkgconfig -name "*.pc" -type f | sort >> "${OUTPUT_PATH}"
fi

if [[ -d /usr/lib/aarch64-linux-gnu/pkgconfig ]]; then
    echo "" >> "${OUTPUT_PATH}"
    echo "=== pkg-config files in /usr/lib/aarch64-linux-gnu/pkgconfig ===" >> "${OUTPUT_PATH}"
    find /usr/lib/aarch64-linux-gnu/pkgconfig -name "*.pc" -type f | sort >> "${OUTPUT_PATH}"
fi

if [[ -d /usr/lib/x86_64-linux-gnu/pkgconfig ]]; then
    echo "" >> "${OUTPUT_PATH}"
    echo "=== pkg-config files in /usr/lib/x86_64-linux-gnu/pkgconfig ===" >> "${OUTPUT_PATH}"
    find /usr/lib/x86_64-linux-gnu/pkgconfig -name "*.pc" -type f | sort >> "${OUTPUT_PATH}"
fi

# 5. Check for specific libraries that ImageMagick might detect
print_info "Checking for specific library files..."
echo "" >> "${OUTPUT_PATH}"
echo "=== Library files that ImageMagick configure might detect ===" >> "${OUTPUT_PATH}"
LIBRARY_PATTERNS=(
    "liblcms2"
    "liblqr"
    "libdjvulibre"
    "libopenexr"
    "libjbig"
    "libtiff"
    "libopenjp2"
)

for lib_pattern in "${LIBRARY_PATTERNS[@]}"; do
    echo "" >> "${OUTPUT_PATH}"
    echo "--- ${lib_pattern} ---" >> "${OUTPUT_PATH}"
    find /usr/lib -name "${lib_pattern}*" -type f 2>/dev/null | head -10 >> "${OUTPUT_PATH}" || true
done

# 6. System information
print_info "Collecting system information..."
echo "" >> "${OUTPUT_PATH}"
echo "=== System Information ===" >> "${OUTPUT_PATH}"
echo "Hostname: ${HOSTNAME}" >> "${OUTPUT_PATH}"
echo "Ubuntu Version: ${UBUNTU_VERSION}" >> "${OUTPUT_PATH}"
echo "Kernel: $(uname -r)" >> "${OUTPUT_PATH}"
echo "Architecture: $(uname -m)" >> "${OUTPUT_PATH}"
echo "Date: $(date)" >> "${OUTPUT_PATH}"

# 7. ALL pkg-config packages (comprehensive list)
print_info "Listing ALL pkg-config packages..."
echo "" >> "${OUTPUT_PATH}"
echo "=== ALL pkg-config packages ===" >> "${OUTPUT_PATH}"
PKG_CONFIG_LIST_FILE="${OUTPUT_PATH}.pkgconfig_all"
> "${PKG_CONFIG_LIST_FILE}"  # Clear file

# Check all standard pkg-config paths
PKG_CONFIG_PATHS=(
    "/usr/lib/pkgconfig"
    "/usr/lib/aarch64-linux-gnu/pkgconfig"
    "/usr/lib/x86_64-linux-gnu/pkgconfig"
    "/usr/share/pkgconfig"
    "/usr/local/lib/pkgconfig"
    "/usr/local/share/pkgconfig"
)

for pkgconfig_dir in "${PKG_CONFIG_PATHS[@]}"; do
    if [[ -d "$pkgconfig_dir" ]]; then
        find "$pkgconfig_dir" -name "*.pc" -type f 2>/dev/null | while read pc_file; do
            pkg_name=$(basename "$pc_file" .pc)
            echo "$pkg_name" >> "${PKG_CONFIG_LIST_FILE}"
        done
    fi
done

# Also use pkg-config --list-all if available
if command -v pkg-config >/dev/null 2>&1; then
    echo "" >> "${OUTPUT_PATH}"
    echo "=== pkg-config --list-all ===" >> "${OUTPUT_PATH}"
    pkg-config --list-all 2>/dev/null | awk '{print $1}' | sort >> "${PKG_CONFIG_LIST_FILE}" || true
fi

sort -u "${PKG_CONFIG_LIST_FILE}" -o "${PKG_CONFIG_LIST_FILE}"

# 7b. Check what pkg-config would find for ImageMagick optional deps (detailed)
print_info "Checking what pkg-config finds for optional ImageMagick dependencies..."
echo "" >> "${OUTPUT_PATH}"
echo "=== pkg-config detection results (ImageMagick deps) ===" >> "${OUTPUT_PATH}"
PKG_CONFIG_CHECKS=(
    "lcms2"
    "liblqr-1"
    "ddjvuapi"
    "OpenEXR"
    "jbig"
    "libtiff-4"
    "libopenjp2"
)

for pkg in "${PKG_CONFIG_CHECKS[@]}"; do
    if pkg-config --exists "$pkg" 2>/dev/null; then
        echo "${pkg}: FOUND" >> "${OUTPUT_PATH}"
        pkg-config --modversion "$pkg" >> "${OUTPUT_PATH}" 2>&1 || true
        pkg-config --libs "$pkg" >> "${OUTPUT_PATH}" 2>&1 || true
        pkg-config --cflags "$pkg" >> "${OUTPUT_PATH}" 2>&1 || true
    else
        echo "${pkg}: NOT FOUND" >> "${OUTPUT_PATH}"
    fi
done

# 8. ALL environment variables
print_info "Collecting ALL environment variables..."
ENV_FILE="${OUTPUT_PATH}.env_all"
env | sort > "${ENV_FILE}"

# Also get specific important env vars
echo "" >> "${OUTPUT_PATH}"
echo "=== Important Environment Variables ===" >> "${OUTPUT_PATH}"
IMPORTANT_ENV_VARS=(
    "PATH"
    "PKG_CONFIG_PATH"
    "LD_LIBRARY_PATH"
    "CPPFLAGS"
    "CFLAGS"
    "CXXFLAGS"
    "LDFLAGS"
    "CC"
    "CXX"
    "CMAKE_PREFIX_PATH"
    "CMAKE_INCLUDE_PATH"
    "CMAKE_LIBRARY_PATH"
)

for var in "${IMPORTANT_ENV_VARS[@]}"; do
    if [[ -n "${!var:-}" ]]; then
        echo "${var}=${!var}" >> "${OUTPUT_PATH}"
    else
        echo "${var}=(unset)" >> "${OUTPUT_PATH}"
    fi
done

print_header "Summary"
echo ""
print_info "Generated files:"
echo "  - ${OUTPUT_PATH} (main report)"
echo "  - ${OUTPUT_PATH}.all (all package names, sorted)"
echo "  - ${OUTPUT_PATH}.dpkg_full (full dpkg -l output)"
echo "  - ${PKG_CONFIG_LIST_FILE} (all pkg-config packages)"
echo "  - ${ENV_FILE} (all environment variables)"
echo ""
print_info "To compare with another system:"
echo "  1. Run this script on both systems"
echo "  2. Compare package lists:"
echo "     diff package_lists/*.all"
echo "     diff package_lists/*.dpkg_full"
echo "  3. Compare pkg-config packages:"
echo "     diff package_lists/*.pkgconfig_all"
echo "  4. Compare environment variables:"
echo "     diff package_lists/*.env_all"
echo "  5. Or use: ./compare_package_lists.sh <file1.all> <file2.all>"
echo ""
print_info "Key packages to check for:"
echo "  - liblcms2-dev (Little CMS)"
echo "  - liblqr-1-0-dev (Liquid Rescale)"
echo "  - libdjvulibre-dev (DJVU)"
echo "  - libopenexr-dev (OpenEXR)"
echo "  - libjbig-dev (JBIG)"
echo "  - libtiff-dev (TIFF)"
echo "  - libopenjp2-dev (OpenJPEG)"

