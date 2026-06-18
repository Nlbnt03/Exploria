<p align="center">
  <img src=".github/banner.png" alt="Keşfedio Banner" width="100%"/>
</p>

# Keşfedio

Keşfedio, gerçek dünyayı bir keşif oyununa dönüştüren mobil uygulamadır. Şehrinde yürüdükçe haritadaki sis kalkar, bölgeleri fetheder ve kaşif kimliğini oluşturursun.

## Özellikler

- **Sis Açma Mekaniği** — Gerçek konumunla hareket ettikçe haritadaki sis kalkar
- **Tekli & Çoklu Mod** — Yalnız veya arkadaşlarınla birlikte keşfe çık
- **Görevler** — Haftalık görevleri tamamla, XP kazan ve seviye atla
- **Rozet Sistemi** — Keşif, sosyal ve seri rozetleriyle koleksiyonunu büyüt
- **Liderlik Tablosu** — Arkadaşlarınla XP yarışına gir, zirveye çık
- **Gerçek Zamanlı Konum** — Mapbox altyapısıyla yüksek doğruluklu harita deneyimi

## Teknolojiler

- [Flutter](https://flutter.dev/) — Cross-platform mobil geliştirme
- [Firebase](https://firebase.google.com/) — Auth, Firestore, Cloud Messaging
- [Mapbox Maps Flutter](https://pub.dev/packages/mapbox_maps_flutter) — Harita ve konum
- [Riverpod](https://riverpod.dev/) — State management

## Kurulum

```bash
git clone https://github.com/Nlbnt03/Exploria.git
cd Exploria
flutter pub get
flutter run
```

> Mapbox token ve Firebase yapılandırması için `lib/app/bootstrap.dart` ve `lib/firebase_options.dart` dosyalarını kendi credentials'larınla güncelle.

## Lisans

Bu proje özel bir projedir. İzinsiz kullanım ve dağıtım yasaktır.
