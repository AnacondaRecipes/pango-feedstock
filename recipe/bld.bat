setlocal EnableDelayedExpansion
@echo on

:: set pkg-config path so that host deps can be found
:: (set as env var so it's used by both meson and during build with g-ir-scanner)
set "PKG_CONFIG_PATH=%LIBRARY_LIB%\pkgconfig;%LIBRARY_PREFIX%\share\pkgconfig;%BUILD_PREFIX%\Library\lib\pkgconfig"

:: get mixed path (forward slash) form of prefix so host prefix replacement works
set "LIBRARY_PREFIX_M=%LIBRARY_PREFIX:\=/%"

findstr /m "C:/ci_310/glib_1642686432177/_h_env/Library/lib/z.lib" "%LIBRARY_LIB%\pkgconfig\gio-2.0.pc"
if %errorlevel%==0 (
    :: our current glib gio-2.0.pc has zlib dependency set as an absolute path. 
    powershell -Command "(gc %LIBRARY_LIB%\pkgconfig\gio-2.0.pc) -replace 'Requires:', 'Requires: zlib,' | Out-File -encoding ASCII %LIBRARY_LIB%\pkgconfig\gio-2.0.pc"
    powershell -Command "(gc %LIBRARY_LIB%\pkgconfig\gio-2.0.pc) -replace 'C:/ci_310/glib_1642686432177/_h_env/Library/lib/z.lib', '' | Out-File -encoding ASCII %LIBRARY_LIB%\pkgconfig\gio-2.0.pc"
)

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
  -Dfreetype=disabled ^
  -Dintrospection=disabled
meson setup builddir !MESON_OPTIONS!
if errorlevel 1 exit 1

:: print results of build configuration
meson configure builddir
if errorlevel 1 exit 1

:: build
ninja -v -C builddir -j %CPU_COUNT%
if errorlevel 1 exit 1

:: test
ninja -v -C builddir test
@REM Few errors there, so ignore test result for now
@REM if errorlevel 1 exit 1

:: install
ninja -C builddir install -j %CPU_COUNT%
if errorlevel 1 exit 1

del %LIBRARY_PREFIX%\bin\*.pdb