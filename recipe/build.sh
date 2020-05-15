#!/bin/bash

if [[ ${target_platform} == osx-64 ]]; then
  rm -rf ${PREFIX}/lib/libuuid*.a ${PREFIX}/lib/libuuid*.la
fi

# Use a sledgehammer to avoid libtool `.la` files when linking; this must be
# done because various packages  we depend on (e.g., libxml2) no longer have
# libtool `.la` files within them.
rm -f ${PREFIX}/lib/libcairo*.la
rm -f ${PREFIX}/lib/libfontconfig*.la
rm -f ${PREFIX}/lib/libfreetype*.la
rm -f ${PREFIX}/lib/libharfbuzz*.la
rm -f ${PREFIX}/lib/libpixman*.la

# We must avoid very long shebangs here.
echo '#!/usr/bin/env bash' > g-ir-scanner
echo "${PYTHON} ${PREFIX}/bin/g-ir-scanner \$*" >> g-ir-scanner
chmod +x ./g-ir-scanner
export PATH=${PWD}:${PATH}

./configure --prefix="${PREFIX}" \
            --host=${HOST} \
            --with-xft \
            --with-cairo="${PREFIX}"

make -j${CPU_COUNT} ${VERBOSE_AT}
# # FIXME: There is one failure:
# ========================================
#    pango 1.40.1: tests/test-suite.log
# ========================================
#
# # TOTAL: 12
# # PASS:  11
# # SKIP:  0
# # XFAIL: 0
# # FAIL:  1
# # XPASS: 0
# # ERROR: 0
#
# .. contents:: :depth: 2
#
# FAIL: test-layout
# =================
#
# /layout/valid-1.markup:
# (/opt/conda/conda-bld/work/pango-1.40.1/tests/.libs/lt-test-layout:5078): Pango-CRITICAL **: pango_font_describe: assertion 'font != NULL' failed
# FAIL test-layout (exit status: 133)
# make check
make install
