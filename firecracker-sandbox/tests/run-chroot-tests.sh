#!/bin/bash
# Run chroot tests: if rootfs is tar.gz, create a 100MB image, extract the
# tarball into a temp dir, copy into the image to form a gold image. For each
# test, copy the gold image to a new file, run the test against it, then
# remove the copy.
#
# Requires: sudo, curl, bin/build/make-image.sh, bin/build/chroot-image.sh
#
# Usage: from project root, run:
#   ./tests/run-chroot-tests.sh
#
# Env:
#   ALPINE_VERSION       Alpine minirootfs version, e.g. 3.23.3 (default: 3.23.3)
#   CHROOT_GOLD_IMAGE    Path for the gold image (default: tests/images/chroot-gold.ext4)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_BUILD="$PROJECT_ROOT/bin/build"

WORKSPACE=`mktemp -d`
trap "rm -rf $WORKSPACE" EXIT
# WORKSPACE=$PROJECT_ROOT/tmp/
# rm -rf $WORKSPACE
# mkdir -p $WORKSPACE
echo "WORKSPACE: $WORKSPACE"

# Alpine: version variable and URL (same pattern as bin/build/build-alpine-rootfs.sh)
# See https://alpinelinux.org/downloads/
ALPINE_VERSION="3.23.3"
ALPINE_MIRROR="https://dl-cdn.alpinelinux.org/alpine"
ALPINE_ARCH="x86_64"
ALPINE_BRANCH="${ALPINE_VERSION%.*}"
MINIROOTFS_URL="$ALPINE_MIRROR/v${ALPINE_BRANCH}/releases/$ALPINE_ARCH/alpine-minirootfs-${ALPINE_VERSION}-$ALPINE_ARCH.tar.gz"

mkdir -p $WORKSPACE

IMAGES_DIR="$PROJECT_ROOT/images"
mkdir -p "$IMAGES_DIR"
ALPINE_ROOTFS="$IMAGES_DIR/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
GOLD_IMAGE="$IMAGES_DIR/chroot-gold.ext4"
if [[ ! -s "$ALPINE_ROOTFS" ]]; then
    echo "Downloading Alpine $ALPINE_VERSION minirootfs..."
    curl -fsSL "$MINIROOTFS_URL" -o "$ALPINE_ROOTFS"
fi

if [[ ! -s "$GOLD_IMAGE" ]]; then
    "$BIN_BUILD/make-image.sh" --size 200M --path "$GOLD_IMAGE"
    sudo $BIN_BUILD/chroot-image.sh --root $GOLD_IMAGE \
        --extract "$ALPINE_ROOTFS" \
        /bin/sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf && apk add bash'
fi

IMAGE=$WORKSPACE/rootfs.ext4

failed_tests=()
passed=0
failed=0

for test_script in $PROJECT_ROOT/tests/chroot/*.sh; do
    [[ -f "$test_script" ]] || continue
    name=$(basename "$test_script")
    echo "Running test $name ..."
    cp $GOLD_IMAGE $IMAGE

    if sudo $BIN_BUILD/chroot-image.sh \
        --root $IMAGE \
        --copy $PROJECT_ROOT/bin:/tmp/bin \
        --copy $PROJECT_ROOT/tests:/tmp/tests \
        /tmp/tests/chroot/$name; then
        echo "PASS: $name"
        passed=$((passed + 1))
    else
        echo "FAIL: $name"
        failed_tests+=("$name")
        failed=$((failed + 1))
    fi
done

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Passed: $passed"
echo "Failed: $failed"
if [[ ${#failed_tests[@]} -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for test in "${failed_tests[@]}"; do
        echo "  - $test"
    done
fi
echo "=========================================="

if [[ $failed -eq 0 ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "$failed test(s) failed."
    exit 1
fi
