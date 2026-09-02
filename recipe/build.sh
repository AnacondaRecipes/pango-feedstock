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

FONTMAP_SRC="${SRC_DIR}/pango/pangofc-fontmap.c"
if ! grep -q '#include <fontconfig/fcfreetype.h>' "$FONTMAP_SRC"; then
    sed -i '/#include <hb-ft.h>/a #include <fontconfig/fcfreetype.h>' "$FONTMAP_SRC"
    echo "Patched: added missing #include <fontconfig/fcfreetype.h> to pangofc-fontmap.c"
fi

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

ninja -v -C builddir -j ${CPU_COUNT}
ninja -C builddir install -j ${CPU_COUNT}