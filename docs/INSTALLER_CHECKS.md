# 0.4.5 PKG kontrol kaydı

22 Ekim 2026 · Geliştirici: Serkan Aydınlı

- Kurulum paketi, yayımlanan ve 88 testle doğrulanan 0.4.5 uygulama ZIP'inden üretildi; uygulama yeniden derlenmedi.
- Son PKG `pkgutil --expand-full` ile açıldı; uygulamanın bütün normal dosyalarının SHA-256 değerleri ZIP'teki uygulamayla eşleşti. Gömülü uygulamada `codesign --verify --deep --strict` başarılı.
- Paket kimliği `local.sikistirici.installer`, sürüm 0.4.5; uygulama build 10. Sabit hedef `/Applications`; relocation kapalı, sürüm ve uygulama kimliği kontrolleri açık.
- Installer dağıtım tanımı Apple Silicon (`arm64`) ve macOS 14+ gerektiriyor; kullanıcı ana dizini kurulumu kapalı. Ek preinstall/postinstall betiği bulunmuyor.
- `installer -showChoicesXML` başarılı. macOS Yükleyici'de logo, geliştirici adı, karşılama metni, hedef seçimi ve standart kurulum ekranı görüldü. Sistem üzerine tam kurulum yapılmadı; yönetici parolası istenmedi.
- PKG imzasızdır; Developer ID Installer ve Apple notarization doğrulaması yapılmadı. Gömülü uygulama yerel ad-hoc imzasını korur.

Yeniden üretme: [README](../README.md) içindeki kurulum paketi komutu.
