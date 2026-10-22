# İmzalama ve Apple noter onayı

0.4.4 derleme betiği uygulama, 7zz ve iki uzantı için Hardened Runtime açar. Varsayılan yerel ad hoc imza Apple Developer ID veya noter onayı değildir.

22 Ekim 2026 yerel kontrolde `security find-identity -v -p codesigning` sıfır geçerli kimlik döndürdü. Dolayısıyla bu makinede Developer ID imzalama ve noter gönderimi doğrulanamadı. Kullanıcı Apple Developer hesabından Developer ID Application sertifikasını Anahtar Zinciri'ne eklemeli ve `xcrun notarytool store-credentials` ile kendi oturumunda bir profil hazırlamalı. Parolayı sohbet veya betik içine yazmamalı.

Kimlik hazır olduğunda:

```sh
SIKISTIRICI_SIGN_IDENTITY='Developer ID Application: Adınız (TEAMID)' \
SIKISTIRICI_APP_PATH='/tam/yol/Sıkıştırıcı.app' ./scripts/build-app.sh
./scripts/notarize-app.sh '/tam/yol/Sıkıştırıcı.app' 'noter-profili' '/tam/yol/Sikistirici-notarized.zip'
```

İmzalı yapı güvenli zaman damgası içerir. Noter betiği kimliği, imzayı, Hardened Runtime ve zaman damgasını kontrol eder; yalnız Developer ID imzalı uygulamayı Apple'a yükler. Kabul yanıtından sonra bileti uygulamaya iliştirir, doğrular, Gatekeeper değerlendirmesini çalıştırır ve son ZIP'i oluşturur. Mevcut çıktı üzerine yazmaz. Kabul edilmeyen işlemde dağıtıma hazır olduğunu söylemez. Apple'a gönderme yalnız bu betiğin açıkça çalıştırılmasıyla yapılır.

Otomatik uygulama güncellemesi bu düzeltmenin kapsamına eklenmedi; mevcut manuel kurulum korunur. İleride güncelleyici eklenirse güncelleme paketlerinin imzaları doğrulanmalıdır.

Kaynaklar: [Apple — Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Apple — Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).
