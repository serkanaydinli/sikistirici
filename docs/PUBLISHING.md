# GitHub yayını için hazırlık

Bu klasör bağımsız depo köküdür. Üst çalışma alanını veya tüm `outputs` klasörünü yüklemeyin.

Önerilen depo adı: `sikistirici`. Açıklama: “Türkçe, açık kaynak macOS arşiv uygulaması — Serkan Aydınlı”. Görünürlük: public. Lisans dosyası depoda MIT olarak hazırdır; GitHub oluşturma ekranında ikinci bir lisans veya README üretmeyin.

Kaynak deposuna `Sources`, `Tests`, `Extensions`, `Vendor`, `packaging`, `scripts`, `docs`, `Package.swift`, README, LICENSE, katkı ve üçüncü taraf bildirimlerini ekleyin. `.gitignore` dosyasını da koruyun. `dist`, `.build`, `work` ve kişisel imzalama anahtarlarını eklemeyin. Arşiv biçimindeki test örnekleri ve `Vendor/7zip` kaynak arşivi kasıtlı olarak kaynak deposuna dahildir.

İlk yayın için `v0.4.5` etiketiyle ön sürüm (pre-release) oluşturun. Açıklama için `docs/RELEASE_NOTES.md` kullanılabilir. Uygulama ZIP'i, kaynak ZIP'i ve SHA-256 dosyasını Release ekleri olarak yükleyin. Uygulamanın Apple Silicon/macOS 14+ gerektirdiğini ve notarization onayı olmadığını açıkça belirtin.

Proje adresi: https://github.com/serkanaydinli/sikistirici . Geliştirici ve depo sahibi: Serkan Aydınlı (`serkanaydinli`). Sürüm adresi: https://github.com/serkanaydinli/sikistirici/releases/tag/v0.4.5 .
