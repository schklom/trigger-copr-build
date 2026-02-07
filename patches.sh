#!/bin/bash

set -euo pipefail

REPO_DIR="tirith-clone"
VERSION_FILE="last_built_version"

# 1. Read version
if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: $VERSION_FILE missing in $(pwd)."
    exit 1
fi
RAW_VERSION=$(cat "$VERSION_FILE")
VERSION=${RAW_VERSION#v}  # Strip 'v' prefix
TARBALL_NAME="tirith-${VERSION}.tar.gz"
SPEC_FILE="$REPO_DIR/rust-tirith.spec" # Spec file path is relative to parent

if [ ! -f "$SPEC_FILE" ]; then
    echo "Error: Spec file not found at $SPEC_FILE"
    exit 1
fi

echo "Preparing build for version: $VERSION"

# 2. Create the Source Tarball from the repo directory
#    We assume 'tirith-clone' is the source. We pack its contents.
#    --transform puts contents into a 'tirith-0.1.8/' folder inside the archive.
echo "Creating source tarball: $TARBALL_NAME from $REPO_DIR..."
tar --exclude-vcs --transform "s|^$REPO_DIR|tirith-${VERSION}|" -czf "$TARBALL_NAME" "$REPO_DIR"

# 3. Patch the Spec File (in place inside the repo folder)

# A. Update Version line
sed -i "s|^Version:.*|Version:        $VERSION|" "$SPEC_FILE"

# B. Skip external dependency check for tirith-core
if ! grep -q "__cargo_skip_build_requires" "$SPEC_FILE"; then
    sed -i '/%global crate tirith/a %global __cargo_skip_build_requires(x) %{x} == tirith-core' "$SPEC_FILE"
fi

# C. Point Source to the new local tarball
sed -i "s|Source:.*%{crates_source}|Source:         $TARBALL_NAME|" "$SPEC_FILE"

# D. Patch Cargo.toml inside the RPM build process
#    (The sed command inside the spec file modifies Cargo.toml during %prep)
MARKER="# Force local path dependency"
if ! grep -q "$MARKER" "$SPEC_FILE"; then
    sed -i "/%cargo_prep/i \\
$MARKER\\
sed -i 's|tirith-core = \"$VERSION\"|tirith-core = { path = \"crates/tirith-core\", version = \"$VERSION\" }|' Cargo.toml" "$SPEC_FILE"
fi

echo "Done. Tarball created at $(pwd)/$TARBALL_NAME and spec file patched."
