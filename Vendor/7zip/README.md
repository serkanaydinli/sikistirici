# 7-Zip 26.04 kaynakları

Değiştirilmemiş resmi kaynak: https://github.com/ip7z/7zip/releases/download/26.04/7z2604-src.tar.xz

SHA-256: `9691944c0fe0d01bb49373a704fb983fd33bc98b1738695179dfbf99ac1734f6`

`COPYING.LGPL-2.1`, bu kaynak arşivindeki `DOC/copying.txt` dosyasının birebir kopyasıdır. `7z2604-src.tar.xz` tam kaynak arşividir; derleme yönergeleri ve diğer lisans metinlerini de içerir. Motor kodu değiştirilmemiştir. Paketleme sırasında yalnız yerel kod imzası uygulanır.

Motor `Sources/SikistiriciApp/Resources/7zz` yolundadır ve ayrı süreç olarak çalışır. Değiştirmek için bu dosyayı uyumlu macOS 7zz derlemesiyle değiştirip `scripts/build-app.sh` çalıştırılabilir. Yeni sürüm kullanılırsa eşleşen kaynak ve lisanslar da güncellenmelidir.

Kaynak arşivi ve LGPL metni uygulamanın `Contents/Resources/` klasörüne de kopyalanır. Ayrıntılı telif ve BSD/unRAR koşulları: [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
