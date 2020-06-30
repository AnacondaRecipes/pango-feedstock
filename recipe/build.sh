#!/bin/bash

if [[ ${target_platform} == osx-64 ]]; then
  rm -rf ${PREFIX}/lib/libuuid*.a ${PREFIX}/lib/libuuid*.la
fi

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
        configure_extra_opts+=(-Dintrospection=true)
        ;;
    osx-64)
        # For now, turn off gobject introspection to avoid a build-time link
        # error (missing "__cg_png_create_info_struct" symbol referenced from
        # the ImageIO Framework system library).
        configure_extra_opts+=(-Dintrospection=false)

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

meson setup \
    --prefix="${PREFIX}" \
    --libdir="${PREFIX}/lib" \
    --wrap-mode="nofallback" \
    --buildtype="release" \
    --backend=ninja \
    -Duse_fontconfig=true \
    ${configure_extra_opts[@]} \
    builddir

# Print build configuration results
meson configure builddir

ninja -C builddir -j ${CPU_COUNT} -v

# Requires third-party font (Cantarell), so turn off for now
#ninja -C builddir -j ${CPU_COUNT} test

ninja -C builddir -j ${CPU_COUNT} install

# Remove any new Libtool files we may have installed. It is intended that
# conda-build will eventually do this automatically.
find "${PREFIX}/lib" -name "*.la" -delete
