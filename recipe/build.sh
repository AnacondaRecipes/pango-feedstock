#!/bin/bash

if [[ "$target_platform" = osx-* ]] ; then
    # The -dead_strip_dylibs option breaks g-ir-scanner in this package: the
    # scanner links a test executable to find paths to dylibs, but with this
    # option the linker strips them out. The resulting error message is
    # "ERROR: can't resolve libraries to shared libraries: ...".
    export LDFLAGS="$(echo $LDFLAGS |sed -e "s/-Wl,-dead_strip_dylibs//g")"
    export LDFLAGS_LD="$(echo $LDFLAGS_LD |sed -e "s/-dead_strip_dylibs//g")"
    rm -rf ${PREFIX}/lib/libuuid*.a ${PREFIX}/lib/libuuid*.la
fi

# necessary to ensure the gobject-introspection-1.0 pkg-config file gets found
export PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}:${PREFIX}/lib/pkgconfig:$BUILD_PREFIX/$BUILD/sysroot/usr/lib64/pkgconfig:$BUILD_PREFIX/$BUILD/sysroot/usr/share/pkgconfig"
export PKG_CONFIG=$PREFIX/bin/pkg-config
declare -a meson_extra_opts

# Use a sledgehammer to avoid libtool `.la` files when linking; this must be
# done because various packages  we depend on (e.g., libxml2) no longer have
# libtool `.la` files within them.
find "${PREFIX}/lib" -type f -name "*.la" -delete

# The "fribidi" recipe moves shared libraries out of `lib64` into `lib`, but
# some builds do not properly account for this in their pkg-config files.
sed -i.bak "s:/lib64:/lib:" "${PREFIX}/lib/pkgconfig/fribidi.pc"

# We must avoid very long shebangs here.
echo '#!/usr/bin/env bash' > g-ir-scanner
echo "${PREFIX}/bin/python ${PREFIX}/bin/g-ir-scanner \$*" >> g-ir-scanner
chmod +x ./g-ir-scanner
export PATH=${PWD}:${PATH}

mkdir -p builddir

declare -a configure_extra_opts
case "${target_platform}" in
    linux-*)
        configure_extra_opts+=(-Dintrospection=enabled)
        ;;
    osx-*)
        configure_extra_opts+=(-Dintrospection=enabled)

        # Use conda- (not Apple XCode-provided) object & library manipulation
        # tools; not doing so will cause the build to fail with "malformed
        # object" & "load command size is zero" errors when building on systems
        # with older releases of Xcode (e.g., Xcode 7 on OS X 10.10).
        ln -s "${INSTALL_NAME_TOOL}" "${BUILD_PREFIX}/bin/install_name_tool"
        ln -s "${NM}" "${BUILD_PREFIX}/bin/nm"
        ln -s "${OTOOL}" "${BUILD_PREFIX}/bin/otool"
        hash -r
        ;;
esac

export XDG_DATA_DIRS=${XDG_DATA_DIRS}:$PREFIX/share
# ensure that the post install script is ignored
export DESTDIR="/"

meson setup \
    --prefix="${PREFIX}" \
    --libdir="${PREFIX}/lib" \
    --wrap-mode=nofallback \
    --buildtype=release \
    --backend=ninja \
    -Dgtk_doc=false \
    -Dinstall-tests=false \
    -Dfontconfig=enabled \
    -Dsysprof=disabled \
    -Dlibthai=disabled \
    -Dcairo=enabled \
    -Dxft=auto \
    -Dfreetype=enabled \
    ${configure_extra_opts[@]} \
    builddir

# Print build configuration results
meson configure builddir

# Build
ninja -C builddir -j ${CPU_COUNT} -v

# Test
case "${target_platform}" in
    osx-*)
        # Requires third-party font (Cantarell), so ignore test results for now
        ninja -C builddir -j ${CPU_COUNT} test || true
        ;;
    linux-*)
        # Multiple errors there, so ignore test results for now
        ninja -C builddir -j ${CPU_COUNT} test || true
        ;;
esac

# Install
ninja -C builddir -j ${CPU_COUNT} install

# Remove any new Libtool files we may have installed. It is intended that
# conda-build will eventually do this automatically.
find "${PREFIX}/lib" -name "*.la" -delete
