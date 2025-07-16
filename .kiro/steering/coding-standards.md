# Kodlama Standartları - Diapalet

## Dart/Flutter Kodlama Kuralları

### Dosya ve Klasör Adlandırma
- Dosya adları: `snake_case` (örn: `goods_receiving_screen.dart`)
- Klasör adları: `snake_case` (örn: `goods_receiving/`)
- Sınıf adları: `PascalCase` (örn: `GoodsReceivingScreen`)
- Değişken/method adları: `camelCase` (örn: `getUserData()`)

### Kod Organizasyonu
- Import'lar alfabetik sırada
- Flutter import'ları önce, sonra package import'ları, en son relative import'lar
- Sınıf üyeleri sırası: fields → constructors → methods
- Private üyeler alt çizgi ile başlar (`_privateMethod`)

### Widget Yapısı
```dart
class MyWidget extends StatelessWidget {
  const MyWidget({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Widget implementation
    );
  }
}
```

### State Management Kuralları
- ViewModel'ler ChangeNotifier extend eder
- UI state değişikliklerinde `notifyListeners()` çağrılır
- Consumer/Selector widget'ları performans için kullanılır
- Context.read() sadece event'lerde, context.watch() build method'unda

### Error Handling
- Try-catch blokları kullanılır
- Kullanıcı dostu hata mesajları gösterilir
- Hata logları debug modda yazılır
- Network hatalarında offline fallback sağlanır

### Localization
- Tüm metinler `'key'.tr()` formatında
- Dil dosyaları `assets/lang/` klasöründe
- Key'ler feature bazında organize edilir (örn: `auth.login_button`)

### Database Operations
- Async/await kullanılır
- Transaction'lar kritik işlemlerde kullanılır
- SQL injection'a karşı parameterized query'ler
- Database helper singleton pattern ile