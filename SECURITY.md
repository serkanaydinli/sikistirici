# Güvenlik

Geliştirici: Serkan Aydınlı. Güvenlik düzeltmeleri en son yayımlanan sürüme uygulanır.

Bir API anahtarı veya özel dosya bulursanız değeri issue, yorum veya ekran görüntüsünde paylaşmayın. Gerçek parolalar ve kişisel arşivler yerine yapay bir örnek kullanın. Açık issue'larda yalnız etkilenen sürümü ve genel sorunu belirtin; güvenlik açığının ayrıntılarını herkese açık yayımlamayın.

Depoda GitHub gizli anahtar taraması/gönderim koruması kullanılır; ek Gitleaks iş akışı commit geçmişini değerleri maskeleyerek kontrol eder. CI taraması gönderim sonrasında çalışır ve bütün özel sır biçimlerini tanıyamaz. `.gitignore`, izlenen dosyaları veya geçmişte yayımlanmış sırları kaldırmaz. Bir gerçek anahtar yayımlanırsa dosyayı silmek yetmez; sağlayıcıdan iptal/değiştirme gerekir.

Yayınlanan uygulamalar kullanıcıya ait derleme yolları açısından kontrol edilir. İndirilen dosyaların SHA-256 değerleri sürüm eklerindedir; bu özetler yayıncı imzasının yerini tutmaz. Beta paketler şu anda Apple Developer ID/notarization onayı taşımaz.
