#!/bin/sh
# set up container to build Sys::OsPackage
# written for issue GH-1 https://github.com/ikluft/Sys-OsPackage/issues/1

# function to print error message and exit
die() {
    echo "error: $*" >&2
    exit 1
}

# check container environment variables
if [ -z "$SYS_OSPKG_TIMESTAMP" ]
then
    die "environment variable SYS_OSPKG_TIMESTAMP must be set"
fi

# set environment variables for build
TMPDIR="logs/$SYS_OSPKG_TIMESTAMP"
SYS_OSPACKAGE_DEBUG=1
export TMPDIR SYS_OSPACKAGE_DEBUG

# check if container filesystem is set up
if [ ! -d "$TMPDIR" ]
then
    die "$TMPDIR directory missing from container environment"
fi
# shellcheck disable=SC2012
num_tarballs="$(ls -1 Sys-OsPackage-*.tar.gz | wc -l)"
if [ "$num_tarballs" -eq 0 ]
then
    die "Sys-OsPackage tarball file required: not found"
fi
if [ "$num_tarballs" -gt 1 ]
then
    die "Sys-OsPackage tarball file required: more than one found"
fi
tarball="$(ls -1 Sys-OsPackage-*.tar.gz)"
srcdir="$(basename "$tarball" .tar.gz)"

# unpack Sys::OsPackage
tar -xf "$tarball"
echo "working directory contents:"
tree -aC
echo
cd "$srcdir" || die "cd to $srcdir failed"

# install prerequisites from CPAN
missing_authordeps="$(dzil authordeps --missing)"
if [ -s "$missing_authordeps" ]
then
    echo "installing missing author dependencies: $missing_authordeps"
    # shellcheck disable=SC2086
    cpanm $missing_authordeps || die install author deps failed
fi
missing_deps="$(dzil listdeps --missing)"
if [ -s "$missing_deps" ]
then
    echo "installing missing dependencies: $missing_deps"
    # shellcheck disable=SC2086
    cpanm $missing_deps || die install author deps failed
fi

# build Sys::OsPackage and run tests
dzil build || die build failed
dzil test || die test failed
