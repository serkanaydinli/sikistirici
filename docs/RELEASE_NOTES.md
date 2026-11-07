# 0.4.6 beta — güvenlik ve gizlilik düzeltmeleri

Geliştirici: **Serkan Aydınlı**.

- Yerel arşiv önizlemesinde tek dosya adı, toplam metadata ve okuma bütçeleri eklendi; sınırı aşan arşivler önizlemede reddedilir.
- Dosya önizlemeleri yalnız kullanıcıya açık geçici oturum dizinlerinde tutulur. Sonraki açılışta önceki çökmelerden kalan sahipsiz oturumlar temizlenir; başka çalışan oturumlara dokunulmaz.
- Dağıtılan çalıştırılabilir dosyalardan kişisel kaynak/derleme yolları kaldırıldı. Paketleme bu yollar kalırsa durur; imzalar temizlemeden sonra uygulanır.
- Ek gizli anahtar dışlama kuralları ve değerleri maskeleyen, salt okuma yetkili Gitleaks iş akışı eklendi.

Apple Silicon · macOS 14+ · Uygulama build 11. PKG, uygulama ZIP'i, kaynak ZIP'i ve SHA-256 listesi sürüm eklerindedir.

**Sınırlar:** Eski 0.4.5 sürümünün ayrı geçici önizleme klasörleri, hâlâ çalışan eski bir uygulamanın verilerini silmemek için otomatik temizlenmez. Native arşiv okumasındaki süre kontrolü libarchive çağrısını her noktada kesebilen bir kesin zaman aşımı değildir; ek okuma/metadata bütçeleri riski sınırlar. Bu değişiklikler bir güvenlik garantisi değildir.

Uygulama ad-hoc imzalıdır; PKG Developer ID Installer ile imzalanmamıştır ve Apple noter onayı yoktur. Sertifika olmadan bu dağıtım eksikliği giderilemedi.

## macOS “Açılmadı” uyarısı

Bu beta sürümün PKG kurulum dosyası Developer ID Installer ile imzalanmamıştır; uygulama yerel ad-hoc imzalıdır ve Apple noter onayı yoktur. Bu nedenle GitHub'dan indirilen dosya açılırken “Apple, kötü amaçlı bir yazılım içermediğini doğrulayamadı” uyarısı görülebilir. Bu mesaj zararlı yazılım tespit edildiği anlamına gelmez; güvenli olduğunun garantisi de değildir.

Dosyayı [bu deponun resmi sürüm sayfasından](https://github.com/serkanaydinli/sikistirici/releases/tag/v0.4.6) indirdiyseniz ve çalıştırmayı seçiyorsanız:

1. Uyarıdaki **Bitti** düğmesine basın.
2. **Sistem Ayarları → Gizlilik ve Güvenlik** bölümünü açın.
3. Güvenlik bölümünde engellenen Sıkıştırıcı dosyasının yanındaki **Yine de Aç** düğmesine basın.
4. macOS'un kimlik doğrulama ve açma onaylarını tamamlayın; ardından kuruluma devam edin.

Bu işlem yalnız seçilen dosya için güvenlik istisnası oluşturur. Seçenek görünmüyorsa dosyayı yeniden açmayı deneyip ayarlara dönün; yönetilen Mac'lerde seçenek yönetici tarafından kısıtlanabilir. Genel Gatekeeper korumasını kapatmanız gerekmez.

Kaynak: [Apple — Mac'inizde uygulamaları güvenle açma](https://support.apple.com/tr-tr/102445). Dağıtımdaki bu uyarının kalıcı çözümü Developer ID imzalama ve Apple noter onayıdır; bu sürümde henüz tamamlanmamıştır.
