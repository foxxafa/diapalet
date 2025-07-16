# UI/UX Rehberi - Diapalet

## Tasarım Prensipleri
- **Kullanıcı Dostu**: Depo çalışanları için basit ve anlaşılır arayüz
- **Hızlı Erişim**: QR kod okuma ve hızlı işlem yapabilme
- **Görsel Geri Bildirim**: İşlem durumları net şekilde gösterilir
- **Responsive**: Farklı ekran boyutlarına uyum

## Tema Sistemi

### Renk Paleti
```dart
// Açık tema
primaryColor: Colors.blue[600]
secondaryColor: Colors.orange[500]
backgroundColor: Colors.grey[50]
surfaceColor: Colors.white

// Koyu tema
primaryColor: Colors.blue[400]
secondaryColor: Colors.orange[400]
backgroundColor: Colors.grey[900]
surfaceColor: Colors.grey[800]
```

### Typography
- **Google Fonts** kullanılır
- Başlıklar: 18-24px, bold
- Body text: 14-16px, regular
- Caption: 12px, light

## Widget Standartları

### Buttons
```dart
// Primary button
ElevatedButton(
  style: ElevatedButton.styleFrom(
    minimumSize: Size(double.infinity, 48),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  child: Text('button_text'.tr()),
  onPressed: onPressed,
)
```

### Form Fields
```dart
// Text input
TextFormField(
  decoration: InputDecoration(
    labelText: 'label'.tr(),
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 12,
    ),
  ),
)
```

### Loading States
```dart
// Loading indicator
Center(
  child: CircularProgressIndicator(),
)

// Shimmer loading for lists
Shimmer.fromColors(
  baseColor: Colors.grey[300]!,
  highlightColor: Colors.grey[100]!,
  child: ListTile(...),
)
```

## Navigation Patterns

### Screen Transitions
- **Push**: Yeni ekrana geçiş
- **Replace**: Mevcut ekranı değiştir
- **Pop**: Geri dön

### Bottom Navigation
- Ana menü için BottomNavigationBar
- 4-5 ana sekme maksimum
- Icon + label kombinasyonu

## Accessibility
- Semantic labels tüm interactive widget'larda
- Minimum touch target: 44x44px
- Yeterli renk kontrastı (4.5:1 minimum)
- Screen reader desteği

## Error States
- Kullanıcı dostu hata mesajları
- Retry butonları
- Offline durumu gösterimi
- Form validation mesajları