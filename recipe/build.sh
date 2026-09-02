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
    export LDFLAGS="$(echo $LDFLAGS |sed -e "s/-Wl,-dead_strip_dylibs//g")"
    export LDFLAGS_LD="$(echo $LDFLAGS_LD |sed -e "s/-dead_strip_dylibs//g")"
fi

export PKG_CONFIG=$BUILD_PREFIX/bin/pkg-config
export PKG_CONFIG_PATH_FOR_BUILD=$BUILD_PREFIX/lib/pkgconfig
export XDG_DATA_DIRS=${XDG_DATA_DIRS}:$PREFIX/share

echo "===== DEBUG: source-level check of the ACTUAL 1.56.4 tarball's pangofc-fontmap.c ====="
# Everything checked so far (headers, versions, pkg-config, the isolated
# probe, the exact ninja compile command) has been fine. The one thing never
# directly inspected is the real on-disk source file this recipe is actually
# compiling - GNOME's public "main" branch is far ahead of 1.56.4, so
# comparing against it was only ever a rough proxy. pango_font_map_add_font_file
# was brand new in 1.56, so its very first cut may have an include-ordering
# issue specific to the 1.56.4 tarball. Dump the real thing directly.
SRC_FONTMAP="${SRC_DIR}/pango/pangofc-fontmap.c"
if [ -f "$SRC_FONTMAP" ]; then
    echo "--- top-of-file #include block (first 60 lines) ---"
    sed -n '1,60p' "$SRC_FONTMAP" | grep -n '#include' || echo "  no #include lines found in first 60 lines"

    echo "--- every #include in the whole file, with line numbers ---"
    grep -n '#include' "$SRC_FONTMAP"

    echo "--- the actual function + context around the FcFreeTypeQueryAll call ---"
    LINE=$(grep -n 'FcFreeTypeQueryAll' "$SRC_FONTMAP" | head -1 | cut -d: -f1)
    if [ -n "$LINE" ]; then
        echo "FcFreeTypeQueryAll referenced at line $LINE of $SRC_FONTMAP"
        start=$((LINE > 40 ? LINE - 40 : 1))
        end=$((LINE + 10))
        sed -n "${start},${end}p" "$SRC_FONTMAP"
    else
        echo "  FcFreeTypeQueryAll not found anywhere in $SRC_FONTMAP !"
    fi
else
    echo "  $SRC_FONTMAP not found - listing pango/ dir instead:"
    find "${SRC_DIR}/pango" -maxdepth 1 -name "pangofc-fontmap*" 2>/dev/null || true
fi
echo "===== END DEBUG ====="

echo "===== DEBUG: checking for duplicate/conflicting fontconfig ====="
echo "PLATFORM=${target_platform}"
echo "PKG_CONFIG=${PKG_CONFIG}"
echo "PKG_CONFIG_PATH=${PKG_CONFIG_PATH}"
echo "PKG_CONFIG_PATH_FOR_BUILD=${PKG_CONFIG_PATH_FOR_BUILD}"
echo "CFLAGS=${CFLAGS}"
echo "CPPFLAGS=${CPPFLAGS}"

echo "--- conda package info: fontconfig in \$PREFIX (host) ---"
conda list -p "$PREFIX" '^fontconfig$' --json 2>/dev/null || conda list -p "$PREFIX" fontconfig || true

echo "--- conda package info: fontconfig in \$BUILD_PREFIX (build) ---"
conda list -p "$BUILD_PREFIX" '^fontconfig$' --json 2>/dev/null || conda list -p "$BUILD_PREFIX" fontconfig || true

echo "--- fontconfig.pc locations ---"
find "${PREFIX}" -name "fontconfig.pc" 2>/dev/null || true
find "${BUILD_PREFIX}" -name "fontconfig.pc" 2>/dev/null || true

echo "--- Version reported by each fontconfig.pc found ---"
for pc in $(find "${PREFIX}" "${BUILD_PREFIX}" -name "fontconfig.pc" 2>/dev/null || true); do
    echo "File: $pc"
    grep -i "^Version" "$pc" || echo "  (no Version line found)"
done

echo "--- What pkg-config actually resolves right now ---"
$PKG_CONFIG --modversion fontconfig || echo "pkg-config could not find fontconfig"
$PKG_CONFIG --cflags fontconfig || echo "pkg-config --cflags failed"

echo "--- Isolated probe: does FcFreeTypeQueryAll compile with just fontconfig cflags? ---"
cat > /tmp/fc_probe.c <<'EOF'
#include <fontconfig/fontconfig.h>
#include <fontconfig/fcfreetype.h>
int probe(void) {
  return (int)(void*)&FcFreeTypeQueryAll;
}
EOF
FC_CFLAGS="$($PKG_CONFIG --cflags fontconfig 2>/dev/null || true)"
if $CC -c $FC_CFLAGS /tmp/fc_probe.c -o /tmp/fc_probe.o 2>&1; then
    echo "PROBE COMPILE: SUCCEEDED (FcFreeTypeQueryAll is visible via pkg-config cflags alone)"
else
    echo "PROBE COMPILE: FAILED -- FcFreeTypeQueryAll is NOT visible even in isolation"
fi
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

export DESTDIR="/"

meson setup builddir \
    --prefix="$PREFIX" \
    --backend=ninja \
    ${MESON_ARGS} \
    "${meson_config_args[@]}" \
    --wrap-mode=nofallback

echo "===== DEBUG: exact pangofc-fontmap.c compile command (isolated, unwrapped) ====="
FONTMAP_TARGET=$(ninja -C builddir -t targets all 2>/dev/null | grep -m1 "pangofc-fontmap\.c\.o:" | cut -d: -f1 || true)
echo "Resolved ninja target: ${FONTMAP_TARGET:-<not found>}"

if [ -n "$FONTMAP_TARGET" ]; then
    ninja -C builddir -t commands "$FONTMAP_TARGET" > /tmp/fontmap_compile_cmd.log 2>&1 || true
    echo "--- exact compile command for $FONTMAP_TARGET ---"
    cat /tmp/fontmap_compile_cmd.log
    echo "--- end compile command ---"
else
    echo "  Could not resolve target name; listing every pangofc-fontmap target found:"
    ninja -C builddir -t targets all 2>/dev/null | grep -i pangofc-fontmap || echo "  none found"
fi
echo "===== END DEBUG ====="

ninja -v -C builddir -j ${CPU_COUNT}
ninja -C builddir install -j ${CPU_COUNT}