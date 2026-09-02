#!/usr/bin/env bash

set -xeo pipefail

# Replace host g-ir-scanner with wrapper that runs build scanner with build python
mv -v "${PREFIX}/bin/g-ir-scanner" "${PREFIX}/bin/g-ir-scanner.real"

cat > "${PREFIX}/bin/g-ir-scanner" <<EOF
#!/usr/bin/env bash
exec "${BUILD_PREFIX}/bin/python" "${BUILD_PREFIX}/bin/g-ir-scanner" "\$@"
EOF
chmod +x "${PREFIX}/bin/g-ir-scanner"

if [[ "$target_platform" = osx-* ]] ; then
    # The -dead_strip_dylibs option breaks g-ir-scanner in this package: the
    # scanner links a test executable to find paths to dylibs, but with this
    # option the linker strips them out. The resulting error message is
    # "ERROR: can't resolve libraries to shared libraries: ...".
    export LDFLAGS="$(echo $LDFLAGS |sed -e "s/-Wl,-dead_strip_dylibs//g")"
    export LDFLAGS_LD="$(echo $LDFLAGS_LD |sed -e "s/-dead_strip_dylibs//g")"
fi

# get meson to find pkg-config when cross compiling
export PKG_CONFIG=$BUILD_PREFIX/bin/pkg-config

# need to find gobject-introspection-1.0 as a "native" (build) pkg-config dep
# meson uses PKG_CONFIG_PATH to search when not cross-compiling and
# PKG_CONFIG_PATH_FOR_BUILD when cross-compiling,
# so add the build prefix pkgconfig path to the appropriate variables
export PKG_CONFIG_PATH_FOR_BUILD=$BUILD_PREFIX/lib/pkgconfig
# export PKG_CONFIG_PATH=$PKG_CONFIG_PATH:$BUILD_PREFIX/lib/pkgconfig

export XDG_DATA_DIRS=${XDG_DATA_DIRS}:$PREFIX/share

echo "===== DEBUG: checking for duplicate/conflicting fontconfig ====="
echo "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
echo "PKG_CONFIG_PATH_FOR_BUILD=${PKG_CONFIG_PATH_FOR_BUILD}"

echo "--- fontconfig.pc locations ---"
find "${PREFIX}" -name "fontconfig.pc" 2>/dev/null
find "${BUILD_PREFIX}" -name "fontconfig.pc" 2>/dev/null

echo "--- fcfreetype.h locations ---"
find "${PREFIX}" -name "fcfreetype.h" 2>/dev/null
find "${BUILD_PREFIX}" -name "fcfreetype.h" 2>/dev/null

echo "--- Version reported by each fontconfig.pc found ---"
for pc in $(find "${PREFIX}" "${BUILD_PREFIX}" -name "fontconfig.pc" 2>/dev/null); do
    echo "File: $pc"
    grep -i "^Version" "$pc" || echo "  (no Version line found)"
done

echo "--- FcFreeTypeQueryAll declared in which headers? ---"
for h in $(find "${PREFIX}" "${BUILD_PREFIX}" -name "fcfreetype.h" 2>/dev/null); do
    echo "File: $h"
    grep -n "FcFreeTypeQueryAll" "$h" || echo "  NOT FOUND in this header"
done

echo "--- What pkg-config actually resolves right now ---"
$PKG_CONFIG --modversion fontconfig || echo "pkg-config could not find fontconfig"
$PKG_CONFIG --cflags fontconfig || echo "pkg-config --cflags failed"
echo "===== END DEBUG ====="

meson_config_args=(
    -Dintrospection=enabled
    -Dfontconfig=enabled
    -Dfreetype=enabled
    -Dcairo=enabled
    -Dsysprof=disabled
    -Dlibthai=disabled
    -Dgtk_doc=false
)

# ensure that the post install script is ignored
export DESTDIR="/"

meson setup builddir \
    --prefix="$PREFIX" \
    --backend=ninja \
    ${MESON_ARGS} \
    "${meson_config_args[@]}" \
    --wrap-mode=nofallback
ninja -v -C builddir -j ${CPU_COUNT}
ninja -C builddir install -j ${CPU_COUNT}
