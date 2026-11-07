# 0.4.6 güvenlik düzeltmeleri

7 Kasım 2026 · Serkan Aydınlı · Build 11

## Değişiklikler

- Native arşiv önizlemesi: dosya adı başına 4 KiB, biriken adlar için 4 MiB ve gerçek okunan/sıkıştırma filtresinden tüketilen veri için 64 MiB bütçe. Swift girdileri biriktirmeden yol denetimi yapılır; normal dosya olmayan girdiler reddedilir. İptal ve süre kontrolü giriş okuma/arama ve başlık sınırlarında uygulanır.
- Önizleme geçici alanı: kök, oturum ve önizleme dizinleri 0700 izinlidir. Kilitler açık oturumları korur; sonraki açılışta kilitsiz, aynı kullanıcıya ait eski oturumlar temizlenir. Sembolik bağlantılar ve dış dizinler izlenmez.
- Dağıtım: debug kaynak yolu bilgileri imzadan önce kaldırılır. Son çalıştırılabilir dosyalarda yerel kullanıcı yolları kalırsa derleme başarısız olur. İmzalar temizlemeden sonra uygulanır.
- Anahtar koruması: ek özel dosya dışlamaları; sabit sürüm ve SHA-256 ile doğrulanan Gitleaks aracıyla salt okuma yetkili, tamamen maskelenmiş GitHub iş akışı. CI gönderimden sonra çalışır; GitHub gönderim korumasının yerini almaz.

## Doğrulama

Birleşik test paketi **100 test, 0 hata** ile geçti (12 yeni test). Önceki kodda aşırı dosya adı/toplam ad bütçesini sınayan iki regresyon testi başarısız oldu; yeni okuyucuda geçti. Geçici alan testleri özel izin, yetim temizliği, etkin oturum, eşzamanlı açılış ve symlink korumasını kapsar. Bağımsız kod incelemesinde bulunan büyük ZIP regresyonu düzeltildi ve yeniden doğrulandı. Yayın paketlerinde gizli anahtar taraması, kişisel yol taraması, imza ve payload karşılaştırması da yapılır.

## Sınırlar

Libarchive içinde çalışmakta olan tek bir çağrı her noktada dışarıdan kesilemez; mutlak CPU/bellek izolasyonu veya kesin duvar saati garantisi verilmez. Büyük/sıkıştırılmış bazı arşivler önizleme bütçesine takılabilir; uygulamadaki normal arşiv işlemleri ayrı sınırlar kullanır.

Çökmüş yeni oturumların temizliği sonraki açılışta gerçekleşir; anlık veya güvenli disk silme garantisi yoktur. İşaretsiz `SikistiriciPreview-UUID` klasörleri, çalışan bir oturuma zarar vermemek için otomatik kaldırılmaz.

Uygulama yerel ad-hoc imzalıdır; PKG Developer ID Installer ile imzalanmamış ve Apple tarafından noter onayı almamıştır. Bu dağıtım güveni eksikliği sertifika olmadan giderilemedi. Güvenlik incelemesi, tüm olası açıkların yokluğunu kanıtlamaz.
