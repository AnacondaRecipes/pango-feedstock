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
export XDG_DATA_DIRS=${XDG_DATA_DIRS}:$PREFIX/share

# Upstream bug in pango 1.56.4: pango_fc_font_map_add_font_file() in
# pangofc-fontmap.c calls FcFreeTypeQueryAll() but the file never includes
# <fontconfig/fcfreetype.h> (only fontconfig.h comes in transitively via
# pangofc-private.h/pangofc-fontmap-private.h), causing an
# implicit-declaration build failure with newer, stricter compiler defaults.
# Patch it in - guarded so this is a no-op if a future point release already
# includes it.
#
# NOTE: done via python, not `sed -i`, because BSD sed (macOS) requires an
# explicit backup-suffix argument to -i while GNU sed (Linux) does not -
# `sed -i 'script'` silently breaks on osx-* runners. Python's behavior is
# identical on every platform this recipe builds on.
FONTMAP_SRC="${SRC_DIR}/pango/pangofc-fontmap.c"
"${BUILD_PREFIX}/bin/python" - "$FONTMAP_SRC" <<'PYEOF'
import sys

path = sys.argv[1]
marker = "#include <hb-ft.h>"
needle = "#include <fontconfig/fcfreetype.h>"

with open(path, "r") as f:
    content = f.read()

if needle not in content:
    if marker not in content:
        sys.exit(f"ERROR: expected marker line not found in {path}: {marker!r}")
    content = content.replace(marker, marker + "\n" + needle, 1)
    with open(path, "w") as f:
        f.write(content)
    print(f"Patched: added missing {needle} to {path}")
else:
    print(f"Already patched: {needle} present in {path}")
PYEOF

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