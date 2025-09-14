
/// GS1 standardındaki barkodları ayrıştırmak için bir yardımcı sınıf.
///
/// Bu sınıf, Application Identifier (AI) içeren barkod dizelerini
/// anlamlı veri parçalarına (GTIN, son kullanma tarihi, seri no vb.) böler.
/// Sabit ve değişken uzunluktaki AI'ları destekler. Değişken uzunluktaki
/// alanların bir ayırıcı karakterle (FNC1 -> ASCII 29) sonlandırıldığı varsayılır.
class GS1Parser {
  /// Bilinen Uygulama Tanımlayıcıları (AI) ve uzunlukları.
  ///
  /// Sabit uzunluklu alanlar için karakter sayısı belirtilir.
  /// Değişken uzunluklu alanlar için `null` kullanılır.
  static const Map<String, int?> _aiDefinitions = {
    // Ana Tanımlayıcılar
    '01': 14, // GTIN (Global Trade Item Number)
    '02': 14, // GTIN of Contained Trade Items

    // Tarihler
    '11': 6, // Production Date (YYMMDD)
    '13': 6, // Packaging Date (YYMMDD)
    '15': 6, // Best Before Date (YYMMDD)
    '17': 6, // Expiration Date (YYMMDD)

    // Lot ve Seri Numarası
    '10': null, // Batch or Lot Number (max 20)
    '21': null, // Serial Number (max 20)

    // Miktar ve Ölçüm
    '30': null, // Count of Items (max 8)
    '310': 6, // Net Weight in kg (AI 310, 1 ondalık basamak)
    '37': null, // Count of trade items contained (max 8)

    // Referanslar ve Tanımlayıcılar
    '240': null, // Additional Product Identification (max 30)
    '241': null, // Customer Part Number (max 30)
    '400': null, // Customer's Purchase Order Number (max 30)
  };

  /// GS1 standartında değişken uzunluklu alanları ayıran karakter.
  /// Genellikle FNC1 sembolü bu karaktere çevrilir (ASCII Group Separator).
  static const String separator = '\x1d';

  /// Ham barkod verisini ayrıştırır ve AI -> Değer eşlemesiyle bir harita döndürür.
  ///
  /// Örnek: '010123456789012810ABC123\x1d17251231'
  /// Sonuç: {'01': '01234567890128', '10': 'ABC123', '17': '251231'}
  static Map<String, String> parse(String rawData) {
    final result = <String, String>{};
    // Bazı tarayıcılar GS1 kodları için bir önek ekler, bu öneki temizle
    String data = rawData.startsWith(']C1') ? rawData.substring(3) : rawData;

    // Veri, görünmez bir grup ayırıcı (FNC1) ile başlayabilir. Bunu temizle.
    if (data.startsWith(separator)) {
      data = data.substring(1);
    }
    
    int currentIndex = 0;
    while (currentIndex < data.length) {
      // Veri dizesinin geri kalanında eşleşen bir AI bul
      String? foundAi;
      int? aiLength;

      // En uzun eşleşmeyi bulmak için (örn. '310' vs '31')
      final matchingAis = _aiDefinitions.keys
          .where((ai) => data.substring(currentIndex).startsWith(ai))
          .toList();
      
      if (matchingAis.isNotEmpty) {
        // En uzun AI'ı seç (örn. '310' '31'den önce gelir)
        matchingAis.sort((a, b) => b.length.compareTo(a.length));
        foundAi = matchingAis.first;
        aiLength = _aiDefinitions[foundAi];
      }

      if (foundAi != null) {
        currentIndex += foundAi.length;
        if (aiLength != null) {
          // Sabit uzunluklu alan
          if (currentIndex + aiLength <= data.length) {
            result[foundAi] = data.substring(currentIndex, currentIndex + aiLength);
            currentIndex += aiLength;
          } else {
            // Hatalı veri, AI için beklenen uzunluk aşıldı.
            // Kalan kısmı bu AI'ye ata ve çık.
            result[foundAi] = data.substring(currentIndex);
            currentIndex = data.length;
            // Hatalı veri - AI için yetersiz uzunluk
            break; 
          }
        } else {
          // Değişken uzunluklu alan
          final separatorIndex = data.indexOf(separator, currentIndex);
          if (separatorIndex != -1) {
            // Ayırıcıya göre böl, bu en güvenilir yöntem.
            result[foundAi] = data.substring(currentIndex, separatorIndex);
            currentIndex = separatorIndex + 1;
          } else {
            // Ayırıcı yok. Bir sonraki AI'nin başlangıcını bularak alanın sonunu tahmin et.
            int nextAiPosition = data.length;
            
            // Mevcut AI'nin hemen sonrasından başlayarak bir sonraki AI'yi ara.
            for (int i = currentIndex + 1; i < data.length; i++) {
              final rest = data.substring(i);
              final isNextAi = _aiDefinitions.keys.any((key) => rest.startsWith(key));
              
              if (isNextAi) {
                 nextAiPosition = i;
                 break;
              }
            }
            
            final value = data.substring(currentIndex, nextAiPosition);
            if (value.isNotEmpty) {
                result[foundAi] = value;
            }
            currentIndex = nextAiPosition;
          }
        }
      } else {
        // Eşleşen bir AI bulunamadı, bu muhtemelen bir GS1 olmayan barkod veya
        // verinin sonudur.
        // Bilinmeyen AI veya veri sonu
        break; // Döngüyü sonlandır
      }
    }

    return result;
  }
} 