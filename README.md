# Firefly

Firefly, eşleştirilmiş iPhone’un pil yüzdesini ve şarj durumunu Mac’in menü çubuğunda gösterir. USB veya Finder üzerinden etkinleştirilmiş Wi-Fi bağlantısını kullanır. Ölçüm alınamadığında panel son başarılı ölçümün zamanını gösterir.

## Kurulum

Apple Silicon ve macOS 27 için hazırlanmıştır. İlk eşleştirme, kablosuz bağlantı, bildirimler ve sorun giderme adımları [kurulum kılavuzunda](KURULUM.md) bulunur.

## Geliştirme

Xcode’da `Firefly.xcodeproj` dosyasını açın ve `Firefly` şemasını seçin. Çekirdek testlerini proje dizininde `swift test` ile çalıştırabilirsiniz. Küçük ve orta boy widget için `FireflyWithWidgets` şeması ile aynı geliştirici takımına ait App Group yapılandırması gerekir.

Swift kaynakları `Sources/`, cihaz oturumunun kaynak kodu `DeviceSession/`, üçüncü taraf bileşen bilgileri ve lisansları `ThirdParty/` altındadır.
