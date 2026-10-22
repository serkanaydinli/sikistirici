# Sıkıştırıcı kullanım kılavuzu

## Başlarken

`Sıkıştırıcı.app` dosyasına çift tıkla. Uygulamalar klasörüne kurulan kopyanın adı `Sıkıştırıcı.app` olur; iki sürümü aynı anda açma. Varsayılan arşiv uygulaması otomatik değiştirilmez.

- **Arşiv aç / ⌘O:** ZIP, 7z, RAR ve desteklenen diğer arşivleri incele, ara ve seçerek çıkar.
- **Önizle / ⌘Y:** seçili dosyayı uygulama içinde Quick Look ile göster.
- **Yeni arşiv / ⌘N:** ZIP/7z, sıkıştırma düzeyi, hazır profil, Mac metadata temizliği ve isteğe bağlı parçalama seç.
- **Parolayla koru:** 7z AES-256 ve dosya adı şifrelemesi. Parola kaydedilmez veya komut satırına yazılmaz.
- **Çıkar / ⌘E:** kapsam, konum, alt klasör, çakışma kuralı ve açılmış boyut sınırını seç.
- **Toplu işlem / ⇧⌘B:** kaynakları ekle, ayrı ayrı sıkıştır veya her arşivi ayrı klasöre çıkar. Çıktı konumunu seçip kuyruğa ekle. Hatalı iş sıradakini durdurmaz.

Dosyaları pencereye sürükleyebilirsin. Tek arşiv açılır; birden çok arşiv toplu çıkarma ekranını açar. Diğer dosyalar yeni arşiv hazırlığına eklenir.

## 0.4.4: inceleme düzeltmeleri

- Çıkarma hedefleri önceden denetlenir. Hata veya iptalde yeni dosyalar kaldırılır, üzerine yazılan eski dosyalar geri getirilir. Geri alma tamamlanamazsa kurtarma yedekleri saklanır ve konumu gösterilir. Normal çıkış, çalışan işlerin iptal/geri alma işlemlerinin bitmesini bekler. Ani güç kesintisi veya zorla sonlandırma için otomatik oturum kurtarma garantisi yoktur.
- Oluşturma kaynak adlarını okuyucuyla aynı kurallara göre kontrol eder; yeni arşiv yayımlanmadan listeleme ve bütünlük testinden geçer.
- Dosya adları görünen şifreli arşivlerde de önizleme, doğrulama ve çıkarma gerektiğinde parola sorup aynı işlemi tekrar dener. Parola diske kaydedilmez.
- Açılışta boyut sınırı aşılırsa doğrudan sınırı yükseltme ve yeniden deneme seçeneği sunulur. Artış kullanıcı tarafından seçilir, en çok 100 GiB'dır; diğer güvenlik kontrolleri korunur.
- Kodlamalı ZIP çıkarmada dosya ve klasör değişiklik tarihleri korunur.
- Seçili dosya çıkarma ve önizleme alan hesabı seçimin boyutuna göre yapılır; bütün arşivin güvenlik denetimi sürer.
- Ana uygulama, motor ve uzantılar Hardened Runtime ile imzalanır. Yerel imza Apple noter onayı değildir. Developer ID ile derleme ve noter gönderimi için [dağıtım yönergesi](DISTRIBUTION.md) eklendi.

## 0.4.3: görsel düzen

Açık temada daha okunaklı koyu turuncu, koyu temada sıcak turuncu vurgu kullanılır. Karşılama ekranında büyük maskot, iki hızlı işlem ve dosya bırakma alanı; yan çubukta simge zeminleri ve üzerine gelme vurguları bulunur. Dosya listesi ile ayrıntı paneli ayrı yüzeylerdir. Tür dağılımına küçük boyut çubukları eklendi. Boş işlem kuyruğu tek satırlık Hazır durumuna indirildi; işler varken ayrıntılı kuyruk görünür.

## 0.4.2: Uygulamalar simgesi

Uygulamalar/Finder simgesi için dış çerçevesi kaldırılmış, maskotu daha büyük yeni LauncherIcon kullanılır. Uygulama içi maskot orijinal AppIcon görselini kullanmaya devam eder.

## 0.4.1: büyük logo, görünüm ve hızlı işlemler

Karşılama maskotu 220 pt, yan çubuk maskotu 64 pt, yeni arşiv maskotu 76 pt olarak büyütüldü. Karşılama ekranı yatay yerleşim ve sıcak turuncu vurgularla yenilendi; kısa pencerelerde kaydırılabilir. Önceki logo animasyonları ve Hareketi azalt desteği korunur.

Yan çubuğun altındaki **Sistem / Açık / Koyu** görünüm seçimi uygulamaya özeldir ve yeniden açılışta korunur. Son açılan arşive sağ tıklayarak Finder’da gösterebilir veya **Geçmişten kaldır** seçebilirsin. Başlığın yanındaki üç nokta bütün geçmiş listesini temizler; arşiv dosyalarını silmez veya açık arşivi kapatmaz. Uzun geçmiş listesi yan çubuk içinde kaydırılır.

Karşılama kartları artık düğmedir: **Hızlı bakış** arşiv seçimini, **Toplu işlem** toplu işlem ekranını, **Yeni paket** arşiv oluşturma ekranını açar.

## 0.4: dosya tarayıcısı ve analiz

- **Arama ve tür filtresi:** bütün arşivde birlikte uygulanır. Belgeler, görseller, video/ses, arşivler ve diğer dosyalar uzantıya göre sınıflandırılır. Arama ve filtre değişince önceki seçim temizlenir. Klasör gezintisinde üstteki yol menüsünden doğrudan bir üst seviyeye geçebilirsin.
- **Sıralama:** ok menüsünden ad, büyükten küçüğe, küçükten büyüğe veya tür seç. Klasörler önce gelir. Sıralama arşiv içeriğini değiştirmez.
- **Analiz / ⇧⌘I:** açılmış boyut dağılımı, şifreli dosya sayısı ve en büyük 10 dosya. Dosyaya tıklamak tarayıcıda konumunu açıp seçer. Boyutlar arşiv başlıklarından alınır; diskte kaplanacak kesin alan tahmini değildir.
- **İçerik listesini kaydet:** Arşiv menüsü veya Analiz ekranından JSON olarak dışa aktar. Dosya yolu, açılmış boyut, klasör ve şifreli bilgisi bulunur. Parola ve dosya içeriği rapora yazılmaz. Rapor mevcut arşivi listeler; kaydedilmemiş düzenlemeleri içermez.
- **Seçim ayrıntıları:** çoklu seçim ve klasörlerde içerideki dosyaların toplamını gösterir; aynı dosyayı iki kez saymaz. Seçili yolları sağ tık menüsünden kopyalayabilirsin.
- **Görünüm:** sade liste, dosya türü simgeleri, sonuçlarda klasör yolu, yenilenen karşılama kartları ve açılıp kapanabilen ayrıntı paneli. Panel tercihi yerel olarak saklanır.

Bu sürüm arama sonrasında kalan görünmez seçimi, çoklu seçimde tek dosya ayrıntısı gösterilmesini ve arşiv kapatıldığında kalan parola isteğini düzeltir. Açılamamış arşivlerde düzenleme/çıkarma/doğrulama devre dışıdır. Motorun bildirmediği sıkıştırılmış dosya boyutu sıfır yerine çizgiyle gösterilir.

## 0.3: dosya adı kodlaması

0.3.1, otomatik açılışta 7zz tarafından çözülemeyen ZIP adı baytlarını algılar. Önce UTF-8, ardından Türkçe Windows-1254 ve CP857 adayları kontrol edilir. Türkçe harf içeren uygun aday bir tahmin olarak seçilir; içerik listesindeki bildirim kullanılan kodlamayı gösterir. Evrensel kodlama tespiti değildir; tahmin yanlışsa elle değiştirilebilir. Seçim listeleme ve çıkarma boyunca tutarlı tutulur.

ZIP açıkken içerik listesindeki **Kodlama** düğmesini veya Arşiv menüsündeki aynı seçeneği kullan. Otomatik, Türkçe Windows-1254, Türkçe DOS CP857 ve UTF-8 seçenekleri var. Önizlemede adları kontrol edip **Bu kodlamayı kullan** seç. Asıl arşiv değişmez; o oturumdaki listeleme, seçerek çıkarma, uygulama içi önizleme, doğrulama ve düzenleme aynı seçimi kullanır. Başka bir arşiv açınca seçim Otomatik olur; kuyruğa alınmış işler kendi seçimini korur.

Elle seçim yalnız tek parçalı `.zip` içindir. Bu yol paketlenmiş libarchive ile okur; UTF-8 bayraklı dosya adları korunur. ZIP kaydındaki yanlış bir Unicode etiketi veya önceden bozulup kaydedilmiş her ad düzeltilemez. Finder'ın boşluk tuşuyla önizlemesi otomatik okumayı sürdürür; elle seçim uygulama içindedir. Düzenlenen ZIP yeniden oluşturulurken adlar Unicode olarak yazılır; sonraki açılışta Otomatik kullanılabilir.

## 0.3: özel profiller ve filtreler

**Yeni arşiv → Profili kaydet ve yönet** bölümünde ad verip kaydet. Biçim, sıkıştırma düzeyi, Mac metadata temizliği, parça boyutu, çıktı klasörü ve filtreler yerel tercihlerde tutulur. Seçili profili güncelleyebilir veya silebilirsin. Parola ve parolayla koruma tercihi profile kaydedilmez; gerektiğinde her işlemde yeniden seçilir. En fazla 100 profil saklanır. Profiller bu sürümde Yeni arşiv ekranında kullanılır; toplu işlem ayarları ayrıdır.

**Dosya filtreleri** ile tam dosya/klasör adlarını dışla, yalnız belirli uzantıları dahil et, yolun bir metin içermesini iste veya alt/üst dosya boyutu belirle. Ad ve uzantıları virgülle ayır; `*`, `?` veya düzenli ifade kullanılmaz. Kurallar birlikte uygulanır. Örnek: `.git, node_modules, .cache` adlarını dışlamak ya da yalnız `pdf, txt` uzantılarını dahil etmek.

**Eklenecekleri önizle** dahil edilen/dışlanan dosyaları ve toplamları gösterir. Görüntülenen listeler sınırlıdır; toplamlar bütün taramayı kapsar. Kaynaklar işlem başında yeniden taranır. Filtreli oluşturma yalnız eşleşen dosyaları özel bir geçici klasöre kopyalar; kaynakları silmez. Klasör yapısı ve Unix izinleri korunur; boş klasörler eklenmez. Ek geçici disk alanı gerekir. Kaynak taraması en fazla 100.000 girdi, filtreli geçici içerik varsayılan olarak 20 GiB ile sınırlıdır. Kaynakların başlık/metadata alanları normal oluşturma yolunun sınırlarına tabidir.

## 0.3: geri al / yeniden yap

Arşive ekleme, silme ve yeniden adlandırma taslağında **⌘Z / ⇧⌘Z**, içerik listesinin altındaki oklar veya Bekleyen değişiklikler ekranındaki düğmeler kullanılabilir. Metin alanında odak varken standart metin geri alma çalışır. **Tümünü bırak** işlemi de aynı oturumda geri alınabilir. En fazla 100 düzenleme adımı tutulur.

Kaydetme başarılı olunca, başka arşiv açınca veya arşivi kapatınca geçmiş temizlenir. Kuyrukta iş varken taslak değiştirilemez. Geri alma diske kaydedilmiş eski arşiv sürümlerini veya uygulama kapandıktan sonraki oturumu kapsamaz.

## Parçalı arşivler

Yeni arşiv ekranında **Parçalara böl** seçeneği var. Özel MiB boyutu veya 25/100/500/2000 MiB hazır boyutlarından birini seç. Parçalar `paket.zip.parçalar` gibi ayrı bir klasöre kaydedilir; mevcut bir kümenin üzerine karışık dosyalar yazılmaz.

Tüm parçaları aynı klasörde tut. `.zip.001`, `.7z.001` ve `.part01.rar` düzenleri tanınır; aradaki bir parçayı açarsan ilk parçaya yönlendirilir. Numaralandırmada boşluk varsa eksik parça adı gösterilir. Son parçanın eksikliği veya içerik hasarı motorun bütünlük/çıkarma denetiminde anlaşılır; dosyalar doğrulama bitmeden hedefe yerleştirilmez. Çok parçalı arşivler düzenlenmez.

## Arşiv düzenleme

Tek parçalı ZIP/7z açıkken **+** ile dosya ekle. Dosya listesinin sağ tık menüsünden **Yeniden adlandır** veya **Arşivden sil** seç. **Değişiklikler / ⌘S** ekranında bekleyen işlemleri gözden geçir.

- **Kaydet:** geçici bir kopya hazırlanır, değişiklikler uygulanır, yeniden sıkıştırılıp doğrulanır; ardından asıl arşiv atomik olarak değiştirilir.
- **Farklı kaydet:** yeni arşiv oluşturur; mevcut çıktı varsa yeni ad kullanır.
- **Tümünü bırak:** bekleyen değişiklikleri siler; asıl arşiv korunur.

Kaydetmeden başka arşive geçme/kapatma sırasında uyarı gösterilir. Parolalı 7z aynı parola ile korunur. Parolalı ZIP düzenleme bu sürümde desteklenmez. Arşivin tamamı yeniden oluşturulduğundan büyük arşivlerde zaman ve ek alan gerekir. Özgün sıkıştırma yöntemi, arşiv yorumu ve tüm özel format metadata alanları korunacağı garanti edilmez; bu sürüm dosya içeriği ve yollarını düzenlemeye yöneliktir. Unix dosya/klasör izinleri korunur; mevcut hedef klasörün izinleri değiştirilmez.

## Finder ve önizleme

Finder sağ tık menüsünde **Sıkıştırıcı ile sıkıştır** ve **Sıkıştırıcı ile çıkar** servisleri bulunur. Sıkıştırma yeni arşiv ekranını; çıkarma hedef konumunu seçebileceğin toplu işlem ekranını açar.

Paket ayrıca FinderSync ve Quick Look `.appex` uzantıları içerir. Uygulamadaki **Finder entegrasyonu** düğmesi macOS uzantı ayarlarını açar. Gerekirse Sistem Ayarları → Genel → Oturum Açma Öğeleri ve Genişletmeler bölümünde Sıkıştırıcı seçeneklerini etkinleştir. Quick Look, paketlenmiş libarchive 3.8.10 ile ayrı motor süreci başlatmadan yalnız içerik listesini okur; arşivden dosya çalıştırmaz veya dosya çıkarmaz. En çok 5.000 satır gösterir. Şifreli başlıklı arşivler için uygulamada parola girerek açman gerekir.

## İşlem özeti ve animasyon

İş kuyruğu geçen süreyi, gerçek kaynak/çıktı boyutlarını, sıkıştırma kazancını veya büyümeyi, parça sayısını gösterir. Yeterli ilerleme verisi geldiğinde yaklaşık kalan süre görünür; çok kısa veya belirsiz aşamalarda tahmin yapılmaz. Her iş başlamadan disk alanı kontrol edilir; bu bir ön kontroldür, eşzamanlı başka uygulamalar alanı tüketirse işlem yine başarısız olabilir.

Logo karşılama ekranında, yan çubukta ve Yeni arşiv ekranında boşta hafifçe nefes alır; üzerine gelince eğilir. İşlem sırasında ritmik sıkıştırma hareketi ve dönen dişli, bitince kısa bir sevinç hareketi ve onay işareti gösterir. Pencere etkin değilken sürekli animasyon durur. macOS **Hareketi azalt** ayarında logo sabit kalır; işlem/onay simgeleri görünür. İşler arka planda sırayla yürür; iptal edilebilir. Kaydetme sırasında birden çok aşama olduğundan ilerleme yüzdesi aşamalar arasında yeniden başlayabilir.

## Veri koruma ve sınırlar

Kaynaklar sıkıştırma/çıkarmada silinmez. Çıkarma varsayılan olarak aynı adlı dosyayı yeniden adlandırır. **Üzerine yaz** özellikle seçildiğinde aynı adlı hedef dosyalar değiştirilir; kaynak arşiv/parçalarının üzerine yazma engellenir. Çıkarma yayınlama aşamasında hata/iptal olursa işlem hedefte yaptığı değişiklikleri geri alır. Geri alma başarısız olursa kurtarma yedeklerini saklar ve konumunu gösterir.

Bağlantılar, güvenli olmayan yollar, kontrol karakterleri ve büyük/küçük harf çakışan girdiler reddedilir. Varsayılan açılmış boyut sınırı 20 GiB; çıkarma ekranında değiştirilebilir. Girdi sınırı 100.000, toplu kaynak sınırı 500, tek motor çağrısı zaman aşımı 20 dakikadır. RAR oluşturma, duraklatıp devam etme ve bulut eşitleme yoktur. Uygulama dosya içeriklerini dışarı göndermez; en fazla sekiz son arşiv yolu yerel tercihlerde saklanır. Fotoğraf/video gibi zaten sıkıştırılmış dosyalarda kazanç sınırlı olabilir.

## Derleme, lisans ve doğrulama

Xcode komut satırı araçları ve Swift gerekir:

```sh
swift test --disable-sandbox
./scripts/build-app.sh
```

`SIKISTIRICI_BUILD_DIR` ve `SIKISTIRICI_APP_PATH` çıktı konumlarını değiştirebilir. Betik Swift uygulamayı ve native uzantıları derler, resmi 7zz motorunu/lisansını paketler, içten dışa Hardened Runtime ile imzalar ve doğrular. Hazır paket arm64'tür.

88 otomatik test geçiyor (22 yeni regresyon testi dahil): eski Türkçe ZIP kodlamaları, kodlamalı parolalı ZIP/CRC hatası, filtre sonuçları, profil kalıcılığı, geri alma ve kuyruk oturumu dahil; ZIP/7z gidiş-dönüşü, parolalar, parçalı arşiv, eksik parça, disk alanı, aktif iptal, dosya adı/yol koruması, çakışmalar, düzenleme, klasör izinleri ve oturum değişimleri. Resmi libarchive RAR4/RAR5 şifreli, sıkıştırılmış ve çok parçalı solid örnekleri kullanıldı; kaynak commit, SHA-256 ve lisans `Tests/ArchiveCoreTests/Fixtures` içindedir. Tüm RAR çeşitleri veya bütün macOS sürümleri için uyumluluk iddiası yoktur.

Motor: resmi 7-Zip 26.04. Telif, LGPL/BSD ve unRAR koşulları [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) ve `7-Zip-License.txt` içinde.
