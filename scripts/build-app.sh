#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="${SIKISTIRICI_BUILD_DIR:-$project_root/.build/package}"
app_path="${SIKISTIRICI_APP_PATH:-$project_root/dist/Sıkıştırıcı.app}"
signing_identity="${SIKISTIRICI_SIGN_IDENTITY:--}"
signing_options=(--force --sign "$signing_identity" --options runtime)
if [ "$signing_identity" != - ]; then
    signing_options+=(--timestamp)
fi
export CLANG_MODULE_CACHE_PATH="$build_root/clang-cache"
mkdir -p "$build_root"
swift build --disable-sandbox -c release --package-path "$project_root" --scratch-path "$build_root/swift-build" --cache-path "$build_root/spm-cache"
binary_path="$(swift build --disable-sandbox -c release --show-bin-path --package-path "$project_root" --scratch-path "$build_root/swift-build" --cache-path "$build_root/spm-cache")/Sikistirici"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/Sikistirici"
cp "$project_root/packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Sources/SikistiriciApp/Resources/"* "$app_path/Contents/Resources/"
cp "$project_root/LICENSE" "$app_path/Contents/Resources/Sikistirici-LICENSE.txt"
cp "$project_root/THIRD_PARTY_NOTICES.md" "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$project_root/Vendor/7zip/COPYING.LGPL-2.1" "$app_path/Contents/Resources/7-Zip-LGPL-2.1.txt"
cp "$project_root/Vendor/7zip/7z2604-src.tar.xz" "$app_path/Contents/Resources/7z2604-src.tar.xz"
chmod +x "$app_path/Contents/Resources/7zz" "$app_path/Contents/MacOS/Sikistirici"
iconset="$build_root/AppIcon.iconset"
mkdir -p "$iconset"
launcher_icon="$app_path/Contents/Resources/LauncherIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$launcher_icon" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$launcher_icon" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_path/Contents/Resources/AppIcon.icns"
codesign "${signing_options[@]}" "$app_path/Contents/Resources/7zz"
# Build native extension executables with Apple's extension entry point.
xcrun clang -O2 -mmacosx-version-min=14.0 -I "$project_root/Sources/CArchivePreview/include" -I "$project_root/Vendor/libarchive/include" -c "$project_root/Sources/CArchivePreview/CArchivePreview.c" -o "$build_root/CArchivePreview.o"
for kind in Finder Preview; do
    extension="$app_path/Contents/PlugIns/Sikistirici${kind}.appex"
    mkdir -p "$extension/Contents/MacOS" "$extension/Contents/Resources"
    cp "$project_root/packaging/${kind}-Info.plist" "$extension/Contents/Info.plist"
    if [ "$kind" = Finder ]; then
        xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -parse-as-library -application-extension -module-cache-path "$build_root/extension-cache" -module-name SikistiriciFinder \
            "$project_root/Sources/ArchiveCore/Models.swift" "$project_root/Sources/ArchiveCore/FinderRequest.swift" "$project_root/Extensions/Finder/FinderSync.swift" \
            -framework Cocoa -framework FinderSync -Xlinker -e -Xlinker _NSExtensionMain -o "$extension/Contents/MacOS/SikistiriciFinder"
    else
        xcrun swiftc -O -swift-version 5 -target arm64-apple-macos14.0 -parse-as-library -application-extension -module-cache-path "$build_root/extension-cache" -module-name SikistiriciPreview \
            -I "$project_root/Sources/CArchivePreview/include" -import-objc-header "$project_root/Sources/CArchivePreview/include/CArchivePreview.h" \
            "$project_root"/Sources/ArchiveCore/*.swift "$project_root/Extensions/Preview/PreviewViewController.swift" "$build_root/CArchivePreview.o" "$project_root/Vendor/libarchive/lib/libarchive.a" \
            -lz -lbz2 -llzma -liconv -framework Cocoa -framework QuickLookUI -Xlinker -e -Xlinker _NSExtensionMain -o "$extension/Contents/MacOS/SikistiriciPreview"
        cp "$project_root/Vendor/libarchive/COPYING" "$extension/Contents/Resources/libarchive-COPYING"
        rm -f "$extension/Contents/MacOS/7zz" "$extension/Contents/Resources/7zz"
    fi
    codesign "${signing_options[@]}" --entitlements "$project_root/packaging/${kind}.entitlements" "$extension"
done
codesign "${signing_options[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Uygulama hazır: %s\n' "$app_path"
