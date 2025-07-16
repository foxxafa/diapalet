# QR Kod ve Barkod Rehberi - Diapalet

## QR Kod Okuma Sistemi
Diapalet'te QR kod okuma, mal kabul ve envanter transfer işlemlerinin temel bileşenidir.

## Mobile Scanner Konfigürasyonu

### Scanner Setup
```dart
// QR kod okuyucu widget
MobileScanner(
  controller: MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  ),
  onDetect: (capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      handleBarcodeResult(barcode.rawValue ?? '');
    }
  },
)
```

### Barcode Intent Service
```dart
// Intent'ten gelen barkod verilerini işleme
class BarcodeIntentService {
  Stream<String> get barcodeStream => _barcodeController.stream;

  void handleIntent(String? data) {
    if (data != null && data.isNotEmpty) {
      _barcodeController.add(data);
    }
  }
}
```

## QR Kod Formatları

### Ürün QR Kodu
```json
{
  "type": "product",
  "product_code": "PRD001",
  "batch_number": "B2024001",
  "expiry_date": "2024-12-31"
}
```

### Lokasyon QR Kodu
```json
{
  "type": "location",
  "location_code": "A01-B02-C03",
  "zone": "A",
  "aisle": "01",
  "shelf": "B02",
  "position": "C03"
}
```

### Palet QR Kodu
```json
{
  "type": "pallet",
  "pallet_id": "PLT2024001",
  "products": [
    {
      "product_code": "PRD001",
      "quantity": 50
    }
  ]
}
```

## QR Kod İşleme Mantığı

### Validation
```dart
bool isValidQRCode(String qrData) {
  try {
    final data = jsonDecode(qrData);
    return data['type'] != null &&
           ['product', 'location', 'pallet'].contains(data['type']);
  } catch (e) {
    return false;
  }
}
```

### Processing
```dart
void processQRCode(String qrData) {
  if (!isValidQRCode(qrData)) {
    showError('invalid_qr_code'.tr());
    return;
  }

  final data = jsonDecode(qrData);
  switch (data['type']) {
    case 'product':
      handleProductQR(data);
      break;
    case 'location':
      handleLocationQR(data);
      break;
    case 'pallet':
      handlePalletQR(data);
      break;
  }
}
```

## Camera Permissions

### Android Permissions
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS Permissions
```xml
<!-- ios/Runner/Info.plist -->
<key>NSCameraUsageDescription</key>
<string>QR kod okumak için kamera erişimi gereklidir</string>
```

## Error Handling

### Camera Errors
- Kamera erişim izni kontrolü
- Kamera kullanılamıyor durumu
- Düşük ışık koşulları uyarısı

### QR Kod Errors
- Geçersiz QR kod formatı
- Tanınmayan ürün kodu
- Geçersiz lokasyon kodu
- Süresi dolmuş ürün uyarısı

## Performance Optimizasyonu

### Scanner Performance
- Detection speed ayarları
- Frame rate optimizasyonu
- Memory usage kontrolü
- Battery usage minimizasyonu

### UI/UX İyileştirmeleri
- Scan overlay ile hedefleme
- Vibration feedback
- Audio feedback (opsiyonel)
- Torch (flaş) kontrolü
- Zoom in/out desteği