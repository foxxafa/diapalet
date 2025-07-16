# Mimari Rehberi - Diapalet

## Proje Yapısı
Diapalet feature-based (özellik bazlı) mimari kullanır:

```
lib/
├── core/         # Paylaşılan bileşenler
│   ├── local/    # SQLite veritabanı işlemleri
│   ├── network/  # API çağrıları ve ağ yapılandırması
│   ├── sync/     # Çevrimdışı veri senkronizasyon
│   ├── theme/    # Tema yönetimi (açık/koyu mod)
│   └── widgets/  # Ortak widget'lar
├── features/     # Ana özellikler
│   ├── auth/                 # Kimlik doğrulama
│   ├── goods_receiving/      # Mal kabul
│   ├── home/                 # Ana ekran
│   ├── inventory_transfer/   # Envanter transfer
│   └── pending_operations/   # Bekleyen işlemler
└── main.dart
```

## Katman Mimarisi
Her feature aşağıdaki katmanları içerir:
- **presentation/**: UI katmanı (screens, widgets, view_models)
- **domain/**: İş mantığı (entities, repositories, use_cases)
- **data/**: Veri katmanı (repositories_impl, data_sources)

## State Management
- **Provider** kullanılır
- ViewModel'ler ChangeNotifier'ı extend eder
- Global state için MultiProvider kullanılır
- Yerel state için StatefulWidget tercih edilir

## Veri Akışı
1. UI → ViewModel → Repository → DataSource
2. Çevrimdışı: SQLite → Sync Service → API
3. Çevrimiçi: API → SQLite (cache)

## Dependency Injection
- Provider paketini kullanarak DI yapılır
- main.dart'ta tüm servisler ve repository'ler sağlanır
- Context.read<T>() ile dependency'ler alınır