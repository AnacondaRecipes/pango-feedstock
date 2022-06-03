setlocal EnableDelayedExpansion
@echo on

:: set pkg-config path so that host deps can be found
:: (set as env var so it's used by both meson and during build with g-ir-scanner)
set "PKG_CONFIG_PATH=%LIBRARY_LIB%\pkgconfig;%LIBRARY_PREFIX%\share\pkgconfig;%BUILD_PREFIX%\Library\lib\pkgconfig"

:: get mixed path (forward slash) form of prefix so host prefix replacement works
set "LIBRARY_PREFIX_M=%LIBRARY_PREFIX:\=/%"

:: configure build using meson
:: https://gitlab.gnome.org/GNOME/pango/-/blob/1.50.7/meson.build
meson setup builddir ^
  --prefix="%LIBRARY_PREFIX_M%" ^
  --wrap-mode=nofallback ^
  --buildtype=release ^
  --backend=ninja ^
  -Dgtk_doc=false ^
  -Dinstall-tests=false ^
  -Dfontconfig=disabled ^
  -Dsysprof=disabled ^
  -Dlibthai=disabled ^
  -Dcairo=enabled ^
  -Dxft=disabled ^
  -Dfreetype=enabled ^
  -Dintrospection=enabled
meson setup builddir !MESON_OPTIONS!
if errorlevel 1 exit 1

:: print results of build configuration
meson configure builddir
if errorlevel 1 exit 1

ninja -v -C builddir -j %CPU_COUNT%
if errorlevel 1 exit 1

ninja -v -C builddir test
if errorlevel 1 exit 1

ninja -C builddir install -j %CPU_COUNT%
if errorlevel 1 exit 1

del %LIBRARY_PREFIX%\bin\*.pdb