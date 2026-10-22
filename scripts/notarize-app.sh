#!/bin/bash
# Submit a Developer ID signed build using an existing Keychain profile.
# Passwords and API secrets are never accepted on this command line.
set -euo pipefail
if [ "$#" -ne 3 ]; then
    printf 'Kullanım: %s /tam/yol/Sıkıştırıcı.app anahtarlık-profili /tam/yol/yeni-dağıtım.zip\n' "$0" >&2
    exit 64
fi
app_path="$1"
profile="$2"
output_zip="$3"
case "$app_path" in /*.app) ;; *) printf 'Tam .app yolu gerekli.\n' >&2; exit 64 ;; esac
case "$output_zip" in /*.zip) ;; *) printf 'Tam .zip çıktı yolu gerekli.\n' >&2; exit 64 ;; esac
if [ -e "$output_zip" ]; then
    printf 'Çıktı zaten var; farklı bir ZIP adı seçin.\n' >&2; exit 65
fi
if [ ! -d "$(dirname "$output_zip")" ]; then printf 'Çıktı klasörü bulunamadı.\n' >&2; exit 65; fi
if [ -z "$profile" ]; then printf 'Mevcut Anahtar Zinciri profili gerekli.\n' >&2; exit 64; fi
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_path/Contents/Info.plist")
if [ "$bundle_id" != local.sikistirici.app ]; then printf 'Beklenmeyen uygulama kimliği.\n' >&2; exit 65; fi
codesign --verify --deep --strict "$app_path"
signature=$(codesign -d --verbose=4 "$app_path" 2>&1)
if ! [[ "$signature" == *"Authority=Developer ID Application:"* && "$signature" == *"(runtime)"* && "$signature" == *"Timestamp="* ]]; then
    printf 'Developer ID Application imzası, Hardened Runtime ve güvenli zaman damgası gerekli.\n' >&2
    exit 65
fi
submission_dir=$(mktemp -d "${TMPDIR:-/tmp}/sikistirici-notary.XXXXXX")
trap 'rm -rf "$submission_dir"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_dir/submission.zip"
# notarytool exits unsuccessfully for non-Accepted results; parse status too.
if ! xcrun notarytool submit "$submission_dir/submission.zip" --keychain-profile "$profile" --wait --output-format plist > "$submission_dir/result.plist"; then
    cat "$submission_dir/result.plist" >&2
    printf 'Noter gönderimi başarısız; dağıtım ZIP’i oluşturulmadı.\n' >&2
    exit 1
fi
status=$(/usr/libexec/PlistBuddy -c 'Print status' "$submission_dir/result.plist")
if [ "$status" != Accepted ]; then
    cat "$submission_dir/result.plist" >&2
    printf 'Apple onayı alınamadı; dağıtım ZIP’i oluşturulmadı.\n' >&2
    exit 1
fi
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
codesign --verify --deep --strict "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"
shasum -a 256 "$output_zip"
printf 'Apple onaylı dağıtım paketi: %s\n' "$output_zip"
