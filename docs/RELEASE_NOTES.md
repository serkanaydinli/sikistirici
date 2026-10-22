# 0.4.5 beta

Geliştirici: **Serkan Aydınlı**.

- Uygulamanın alt bölümüne geliştirici adı ve açık kaynak sürüm bilgisi eklendi.
- Özgün proje kodu, belgeler ve maskot görselleri MIT lisansı ile paylaşılmaya hazırlandı.
- Üçüncü taraf bildirimleri korundu; 7-Zip'in eşleşen kaynak arşivi ve tam LGPL metni hem depoya hem uygulama paketine eklendi.
- Bağımsız depo düzeni için derleme çıktıları `dist/` ve `.build/package/` altına taşındı; Git dışlama kuralları, kullanım ve katkı rehberleri eklendi.
- 0.4.4'teki parola tekrarları, boyut sınırı, zaman damgaları, seçili içerik bütçesi ve hata/iptal sonrası geri alma düzeltmeleri korundu.

Paket: Apple Silicon, macOS 14+. Yerel ad-hoc imzalı beta; Apple Developer ID/notarization onayı yoktur. Uygulama sürümü 0.4.5, build 10.

Logo ve geliştirici bilgisi içeren macOS `.pkg` kurulum dosyası da eklendi. Uygulamayı `/Applications` klasörüne kurar; Apple Silicon ve macOS 14+ gerektirir. Kurulum öncesinde uygulamayı kapatın. PKG, Developer ID Installer ile imzalanmamıştır.

Yayın dosyaları: `Sikistirici-0.4.5-macOS-arm64.pkg`, `Sikistirici-0.4.5-macOS-arm64.zip`, `Sikistirici-0.4.5-source.zip` ve `SHA256SUMS-0.4.5.txt`.

## macOS “Açılmadı” uyarısı

Bu beta sürümün PKG kurulum dosyası Developer ID Installer ile imzalanmamıştır; uygulama yerel ad-hoc imzalıdır ve Apple noter onayı yoktur. Bu nedenle GitHub'dan indirilen dosya açılırken “Apple, kötü amaçlı bir yazılım içermediğini doğrulayamadı” uyarısı görülebilir. Bu mesaj zararlı yazılım tespit edildiği anlamına gelmez; güvenli olduğunun garantisi de değildir.

Dosyayı [bu deponun resmi sürüm sayfasından](https://github.com/serkanaydinli/sikistirici/releases/tag/v0.4.5) indirdiyseniz ve çalıştırmayı seçiyorsanız:

1. Uyarıdaki **Bitti** düğmesine basın.
2. **Sistem Ayarları → Gizlilik ve Güvenlik** bölümünü açın.
3. Güvenlik bölümünde engellenen Sıkıştırıcı dosyasının yanındaki **Yine de Aç** düğmesine basın.
4. macOS'un kimlik doğrulama ve açma onaylarını tamamlayın; ardından kuruluma devam edin.

Bu işlem yalnız seçilen dosya için güvenlik istisnası oluşturur. Seçenek görünmüyorsa dosyayı yeniden açmayı deneyip ayarlara dönün; yönetilen Mac'lerde seçenek yönetici tarafından kısıtlanabilir. Genel Gatekeeper korumasını kapatmanız gerekmez.

Kaynak: [Apple — Mac'inizde uygulamaları güvenle açma](https://support.apple.com/tr-tr/102445). Dağıtımdaki bu uyarının kalıcı çözümü Developer ID imzalama ve Apple noter onayıdır; bu sürümde henüz tamamlanmamıştır.
