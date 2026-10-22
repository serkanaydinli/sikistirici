#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$#" -ne 2 ]; then
    printf 'Kullanım: %s /tam/yol/Sıkıştırıcı.app /tam/yol/Sikistirici.pkg\n' "$0" >&2
    exit 64
fi
app_path="$1"
output_path="$2"
case "$app_path" in /*) ;; *) echo 'Uygulama yolu mutlak olmalı.' >&2; exit 64;; esac
case "$output_path" in /*.pkg) ;; *) echo 'Çıktı mutlak bir .pkg yolu olmalı.' >&2; exit 64;; esac
[ -d "$app_path" ] && [ -d "$(dirname "$output_path")" ] || { echo 'Uygulama veya çıktı klasörü yok.' >&2; exit 66; }
[ ! -e "$output_path" ] || { echo 'Çıktı zaten var; üzerine yazılmadı.' >&2; exit 73; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Contents/Info.plist")
[ "$identifier" = local.sikistirici.app ] || { echo 'Beklenmeyen uygulama kimliği.' >&2; exit 65; }
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app_path/Contents/Info.plist")
/usr/bin/codesign --verify --deep --strict "$app_path"
staging=$(mktemp -d "${TMPDIR:-/tmp}/sikistirici-installer.XXXXXX")
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root" "$staging/resources"
/usr/bin/ditto "$app_path" "$staging/root/Sıkıştırıcı.app"
/usr/bin/pkgbuild --analyze --root "$staging/root" "$staging/components.plist"
# Avoid searching for and replacing copies outside /Applications. Replace the
# app atomically and refuse downgrades; no privileged installer scripts run.
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsRelocatable false' "$staging/components.plist" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$staging/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleIsVersionChecked true' "$staging/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleHasStrictIdentifier true' "$staging/components.plist"
/usr/libexec/PlistBuddy -c 'Set :0:BundleOverwriteAction upgrade' "$staging/components.plist"
/usr/bin/pkgbuild --root "$staging/root" --component-plist "$staging/components.plist" \
    --identifier local.sikistirici.installer --version "$version" --install-location /Applications \
    --ownership recommended "$staging/Sikistirici-component.pkg"
cp "$project_root/packaging/installer/"* "$staging/resources/"
cp "$app_path/Contents/Resources/LauncherIcon.png" "$staging/resources/LauncherIcon.png"
/usr/bin/productbuild --synthesize --package "$staging/Sikistirici-component.pkg" "$staging/Distribution.xml"
# Use Foundation to preserve generated package refs while adding platform
# requirements and the branded welcome screen. No Python dependency required.
/usr/bin/swift "$project_root/scripts/configure-installer.swift" "$staging/Distribution.xml" "$staging/resources"
/usr/bin/productbuild --distribution "$staging/Distribution.xml" --resources "$staging/resources" \
    --package-path "$staging" "$output_path"
printf 'Kurulum dosyası hazır (imzasız): %s\n' "$output_path"
