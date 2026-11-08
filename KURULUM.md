# Firefly’ı kullanma

Bu paket Apple Silicon ve macOS 27 için hazırlanmıştır. iPhone okuma araçları uygulamanın içindedir. Homebrew veya iPhone’a ek uygulama kurmak gerekmez.

1. Çalışan Firefly varsa panelin sağ üstündeki güç düğmesiyle çıkın. Firefly-macOS.zip dosyasını açın veya teslim edilen Firefly.app dosyasını kullanın.
2. Firefly.app’i Uygulamalar klasörüne sürükleyip çift tıklayın. Üst menü çubuğundaki ateş böceği simgesine tıklayın.
3. İlk eşleştirmede iPhone’u USB ile bağlayın ve kilidini açın. İstenirse Finder’da ve iPhone’da güveni onaylayın. Panelde Yenile’ye basın. Cihaz adı, USB, yüzde ve son başarılı ölçüm zamanı görünmelidir.
4. Kablosuz kullanım için kablo bağlıyken Finder’da iPhone’u seçin. Genel bölümünde “Wi-Fi ağına bağlıyken bu iPhone’u göster” seçeneğini açıp Uygula’ya basın. Mac ve iPhone aynı yerel ağdayken kabloyu çıkarın. Yenile’den sonra panelde Wi-Fi ve yeni ölçüm zamanını kontrol edin. Bu Mac ve iPhone üzerinde her iki yöntem de denendi.

## Günlük kullanım

Pil sekmesinde en son başarılı ölçümün zamanını ve kaynağını görebilirsiniz. Yeni veri alınamazsa eski değer son bilinen ölçüm olarak ayrılır. Geçmiş sekmesi 24 saatlik ve 7 günlük gerçek ölçümleri gösterir. Noktalar arasındaki boşluklar doldurulmaz. CSV dışa aktarımı seçili cihazın saklanan geçmişini içerir. Şarj tahmini yalnızca aynı cihaza ait yeterli sayıda yakın ve kesintisiz şarj ölçümü olduğunda görünür.

Ayarlar’dan Türkçe veya İngilizceyi, menü çubuğu görünümünü ve bildirimleri seçebilirsiniz. Bildirimleri etkinleştirirken macOS izin isteyebilir. Düşük pil uyarıları eşik geçişlerine dayanır. İlk ölçüm tek başına geçiş sayılmaz. Planlanan kontrolün çalışması için seçilen dakika içinde Mac uyanık, Firefly açık ve iPhone erişilebilir olmalıdır. Uygulama Mac’i uyandırmaz. Bildirim almak için bildirimleri de açın.

## Pil görünmüyorsa

- Yardım sekmesindeki açıklamayı okuyup Yeniden dene’ye basın. Telefonu USB ile bağlayıp kilidini açarak başlayın. Bir güven istemi görürseniz onaylayın.
- USB çalışıyor, Wi-Fi çalışmıyorsa Finder seçeneğini ve iki cihazın aynı ağda olduğunu kontrol edin. Finder’da görünmesi tek başına pil bilgisinin okunabildiğini göstermez.
- Cihaz yanıt vermiyorsa Firefly zaman aşımından sonra sorguyu sonlandırır. Geçici hatalarda en fazla altı deneme yapar. Mac’in uyanması, ağ erişiminin geri gelmesi veya Yeniden dene düğmesi yeni bir deneme başlatır.
- Okuma araçları eksik görünüyorsa dağıtım ZIP’inden uygulamayı bütün olarak yeniden kopyalayın. Araçlar ayrı kurulmuşsa Firefly standart Homebrew yollarını da denetler.
- Pil uyarısı görünmüyorsa hem Firefly ayarlarını hem macOS Sistem Ayarları → Bildirimler → Firefly iznini kontrol edin.

## Kaynak proje ve dağıtım

Xcode’da Firefly.xcodeproj dosyasını açın. Yerel menü çubuğu uygulaması için Firefly şemasını seçin. Çekirdek testleri proje dizininde `swift test` ile yürütülür. Yerel paket kendi Mac’inizde geliştirme ve kullanım için geçici kod imzası taşır. Developer ID imzası ve Apple noter onayı alınmadı.

Küçük ve orta boy widget için ayrı FireflyWithWidgets şeması vardır. Uygulama ve uzantıda aynı geliştirici takımını ve bu takıma ait App Group yetkisini yapılandırın. Widget yalnızca paylaşılan son ölçümü okur. Bu şemanın derlemesi doğrulandı. İmzalı ortak veri alanı, widget galerisinden ekleme ve masaüstündeki yenileme davranışı bu teslimde sınanmadı. Ana dağıtım paketi menü çubuğu sürümüdür.

Pil geçmişi kullanıcıya ait Application Support/Firefly dizininde, tercihler ise yerel kullanıcı ayarlarında tutulur. Firefly eşleştirme anahtarlarını kopyalamaz. Okuma araçları libimobiledevice 1.4.0 Homebrew dağıtımından alınmıştır. ThirdParty/manifest.json sürümleri, kaynak adreslerini ve sağlama toplamlarını listeler. Üçüncü taraf lisansları ve ilgili kitaplıkların kaynak arşivleri ThirdParty altındadır.

0.1.2 sürümünde Pil sekmesi içeriğe göre kısalır. Menü simgesi güncel bir ölçümde pil %20’nin altındaysa sistem kırmızısına, %20 veya üzerindeyken şarj oluyorsa sistem yeşiline döner. Diğer durumlarda standart menü çubuğu rengini kullanır.

0.1.3 sürümü eşleştirilmiş iPhone ile açık bir oturum üzerinden ölçüm alır. iPhone ağ hizmetini sunuyorsa ekran kilitliyken de çalışabilir. iOS Wi-Fi erişimini tamamen durdurursa canlı ölçüm alınamaz. Telefon ağda yeniden duyurulduğunda Firefly bağlantıyı tekrar dener. İlk bağlantı için kilidi açmak gerekebilir. Panel açıkken başarılı okumalar arasında 1 saniye, kapalıyken 3 saniye, Mac’in düşük güç modunda panel kapalıyken 10 saniye bekler. Cihazın yanıt süresi bu aralığa eklenir. Logo menü çubuğuna sığacak şekilde en fazla 22 puntodur. Renk geçişi 0,24 saniye sürer; Hareketi Azalt ayarı açıksa animasyon kullanılmaz.

0.1.5 ile Wi-Fi'da geciken pil yanıtı için en fazla 15 saniye beklenir. Hızlı denemeler bittikten sonra Firefly eşleştirilmiş cihazın Mac’in USB veya ağ cihazı listesine dönüp dönmediğini yaklaşık dakikada bir kontrol eder. Cihaz listede görünmezken yeni bir oturum açılmaz. Mac uykudayken kontroller durur. Son 40 bağlantı olayı Application Support/Firefly içindeki connection-events.txt dosyasına yalnızca saat, sonuç ve bağlantı türüyle kaydedilir.

0.1.6 — Sekme şeridini yatay kaydırabilir veya panel içeriğinde sağa/sola sürükleyerek sekme değiştirebilirsiniz. Mobil verideki bir iPhone için Ayarlar → Mobil veriden pil bildirimi bölümünden isteğe bağlı iCloud dosyasını seçin. [Kestirme kurulum adımları](Resources/DeviceTools/MobileSetup.html). Yüzde yalnızca iPhone’daki kestirme çalışıp eşitleme tamamlandığında güncellenir.

## Sürükleyerek kurulum ve yeni sürüm paketleme

GitHub Releases’tan Mac’inize uygun DMG dosyasını indirin ve açın. Penceredeki Firefly uygulamasını sağdaki Applications klasörüne sürükleyin. Kopyalama tamamlandıktan sonra Firefly diskini çıkarın ve uygulamayı Uygulamalar’dan açın.

Yerel sürüm hazırlamak için macOS üzerinde proje kökünden çalıştırın:

```sh
Scripts/build-dmg.sh /path/to/Firefly.app ./dist
```

İlk girdi resmî sürüm ZIP’i de olabilir. Betik ikonları doğrudan uygulamadan alır. Uygulamanın imzasını doğrular; kaynak uygulamayı değiştirmeden sürüm ve mimariye göre DMG adını üretir. 800 × 500 Finder penceresi ve Retina görseli her derlemede aynı tasarım tarifinden hazırlanır. Python paketleri sürüm ve SHA-256 özetiyle sabitlenmiştir.

Yeni GitHub sürümünde önce imzalı uygulamayı içeren `Firefly-VERSION-macOS-arm64.zip` dosyasını sürüm taslağına ekleyin, sonra `vVERSION` etiketiyle yayımlayın. **Package Firefly installer** iş akışı DMG’yi oluşturur, bağlayarak kontrol eder ve aynı sürüme ekler. ZIP sonradan eklendiyse Actions bölümünden aynı iş akışını ilgili etiketle çalıştırabilirsiniz. Paketleyici Developer ID imzası ya da Apple noter onayı üretmez.

## Uygulama içinden güncelleme

Güncelleyiciyi içeren ilk sürümü Uygulamalar’a kopyalayıp oradan açın. Firefly ilk açılışta, sonra en fazla saatte bir Pages üzerindeki appcast.xml dosyasına bakar. Daha yeni, uyumlu bir sürüm varsa bağlantı durumunun yanında Güncelleme var / Update available düğmesi görünür. Düğme Sparkle’ın indirme, doğrulama ve yeniden başlatma penceresini açar. Yazmaya izin verilmeyen bir konumda macOS onay isteyebilir.

Sürüm hazırlayan kişi yeni CFBundleVersion değeriyle uygulamayı derleyip imzalar. Firefly-VERSION-macOS-arm64.zip arşivini vVERSION GitHub sürümüne ekler. Sparkle dağıtımındaki bin klasörünü SPARKLE_TOOLS ile belirtip Scripts/prepare-update.sh komutuna bu ZIP’i verir. Betik doğru açık anahtarı ve imzayı doğrulamadan beslemeyi değiştirmez. Üretilen docs/updates/appcast.xml dosyasını Pages’a yayımlayın. Kullanıcı yalnızca imzalanmış ZIP güncellemesini indirir. DMG ilk kurulum için kalır.
