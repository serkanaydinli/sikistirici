# Katkıda bulunma

Sıkıştırıcı'nın geliştiricisi ve proje yürütücüsü **Serkan Aydınlı**.

Apple Silicon bir Mac, macOS 14+ ve Swift 6.0+ içeren Xcode gerekir. Depo kökünde:

```sh
swift test --disable-sandbox
./scripts/build-app.sh
```

Derlenen uygulama `dist/Sıkıştırıcı.app` yoluna yazılır. Normal geliştirmede Developer ID sertifikası gerekmez; paket yerel ad-hoc imzalıdır. Dağıtım için [imzalama yönergesini](docs/DISTRIBUTION.md) oku.

Hata bildirirken macOS ve uygulama sürümünü, tekrar üretme adımlarını, beklenen ve gerçekleşen sonucu belirt. Gerçek kişisel arşivler, parolalar, dosya listeleri veya imzalama anahtarları paylaşma; küçük ve yapay bir örnek kullan.

Değişiklikleri tek bir sorun etrafında tut. Hata düzeltmelerine hatayı yeniden üreten bir test ekle; arayüz değişikliklerini açık ve koyu görünümde denetle. Kaynak dosyaları koruma, güvenli yol denetimi, boyut sınırı ve parola gizliliği davranışlarını koru. Üçüncü taraf kod ve örneklerin kaynak/lisans bilgilerini ekle.

Gönderdiğin proje katkıları, aksi açıkça belirtilmedikçe projenin MIT lisansı kapsamında değerlendirilir. Üçüncü taraf bileşenler kendi lisanslarını korur.
