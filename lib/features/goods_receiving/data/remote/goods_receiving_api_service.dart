// features/goods_receiving/data/remote/goods_receiving_api_service.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../domain/entities/purchase_order.dart';
import '../../domain/entities/purchase_order_item.dart';
import '../models/goods_receipt_payload.dart';

/// Mal kabulü ile ilgili uzak sunucu (API) işlemlerini tanımlar.
/// Bu arayüz, hem online hem de offline senaryolar için veri kaynağını soyutlar.
abstract class GoodsReceivingRemoteDataSource {
  /// Sunucudan durumu "açık" veya "kısmi" olan tüm satın alma siparişlerini getirir.
  Future<List<PurchaseOrder>> fetchOpenPurchaseOrders();

  /// Belirli bir sipariş ID'sine ait tüm sipariş kalemlerini (ürünleri) getirir.
  Future<List<PurchaseOrderItem>> fetchPurchaseOrderItems(int orderId);

  /// Yapılan mal kabul işlemini (kabul edilen ürünler ve miktarları) sunucuya gönderir.
  /// Sunucu bu veriyi alıp ilgili siparişin durumunu güncellemeli ve stok hareketlerini işlemelidir.
  Future<bool> postGoodsReceipt(GoodsReceiptPayload payload);
}

/// [GoodsReceivingRemoteDataSource] arayüzünün canlı API ile çalışan gerçeklemesi.
class GoodsReceivingRemoteDataSourceImpl implements GoodsReceivingRemoteDataSource {
  final Dio _dio;

  // Dio istemcisini dışarıdan alarak veya burada oluşturarak yapılandırın.
  // Gerçek base URL'nizi buraya girmelisiniz.
  GoodsReceivingRemoteDataSourceImpl({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: "https://api.rowhub.com/v1"));

  /// API'den açık satın alma siparişlerini çeker.
  ///
  /// Bu metod, sunucudaki `satin_alma_siparis_fis` tablosuna bir GET isteği atar.
  /// `status` alanı 0 (Açık) veya 1 (Kısmi) olan kayıtları hedefler.
  /// Ayrıca `tedarikci` tablosu ile JOIN yaparak tedarikçi adını da alır.
  /// SQL Örneği:
  /// SELECT f.*, t.tedarikci_adi FROM satin_alma_siparis_fis f
  /// LEFT JOIN tedarikci t ON f.tedarikci_id = t.id
  /// WHERE f.status IN (0, 1);
  @override
  Future<List<PurchaseOrder>> fetchOpenPurchaseOrders() async {
    debugPrint("API: Fetching open purchase orders from remote...");
    try {
      // Sunucu tarafında bu endpoint'in 'status=open' veya benzeri bir filtreyi
      // desteklediğini varsayıyoruz.
      final response = await _dio.get('/purchase-orders', queryParameters: {'status': 'open'});
      
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((json) => PurchaseOrder.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load purchase orders. Invalid data format.');
      }
    } on DioError catch (e) {
      // Hata yönetimi (logging, kullanıcıya mesaj gösterme vb.)
      debugPrint("API Error fetching purchase orders: $e");
      // Uygulamanın çökmemesi için hatayı yeniden fırlatmak veya
      // kullanıcı dostu bir mesajla yönetmek önemlidir.
      rethrow;
    }
  }

  /// Belirli bir siparişin kalemlerini API'den çeker.
  ///
  /// Bu metod, sunucudaki `satin_alma_siparis_fis_satir` tablosuna bir GET isteği atar.
  /// Belirtilen `orderId` (siparis_id) ile eşleşen kayıtları getirir.
  /// Ayrıca `urunler` tablosu ile JOIN yaparak ürün adı, barkod gibi detayları da alır.
  /// SQL Örneği:
  /// SELECT s.*, u.UrunAdi, u.StokKodu, u.Barcode1, u.qty, u.palletqty FROM satin_alma_siparis_fis_satir s
  /// LEFT JOIN urunler u ON s.urun_id = u.UrunId
  /// WHERE s.siparis_id = :orderId;
  @override
  Future<List<PurchaseOrderItem>> fetchPurchaseOrderItems(int orderId) async {
    debugPrint("API: Fetching items for order ID: $orderId from remote...");
    try {
      final response = await _dio.get('/purchase-orders/$orderId/items');
      
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((json) => PurchaseOrderItem.fromJson(json))
            .toList();
      } else {
        throw Exception('Failed to load purchase order items. Invalid data format.');
      }
    } on DioError catch (e) {
      debugPrint("API Error fetching order items: $e");
      rethrow;
    }
  }

  /// Tamamlanan mal kabul işlemini sunucuya kaydeder.
  ///
  /// Bu metod, sunucuya bir POST isteği atarak [payload] içeriğini gönderir.
  /// Sunucu tarafında bu isteği karşılayan bir endpoint (örn: /goods-receipts) olmalıdır.
  /// Bu endpoint:
  /// 1. Gelen veriyi (`GoodsReceiptPayload`) veritabanına kaydeder (yeni bir 'mal_kabul_fis' tablosu olabilir).
  /// 2. `satin_alma_siparis_fis_satir` tablosundaki ilgili ürünlerin gelen miktarını günceller.
  /// 3. `satin_alma_siparis_fis` tablosunun durumunu kontrol eder (tüm kalemler geldiyse 'Kapalı' yapar).
  /// 4. `urunler` tablosundaki stok miktarını günceller.
  /// 5. Palet oluşturulduysa, palet bilgisini kaydeder.
  @override
  Future<bool> postGoodsReceipt(GoodsReceiptPayload payload) async {
    debugPrint("API: Sending goods receipt for order ID: ${payload.purchaseOrderId} to remote...");
    try {
      final response = await _dio.post('/goods-receipts', data: payload.toJson());
      
      // Genellikle 201 (Created) veya 200 (OK) başarılı kabul edilir.
      if (response.statusCode == 201 || response.statusCode == 200) {
        debugPrint("API: Goods receipt sent successfully.");
        return true;
      } else {
        debugPrint("API: Failed to send goods receipt. Status: ${response.statusCode}");
        return false;
      }
    } on DioError catch (e) {
      debugPrint("API Error sending goods receipt: $e");
      // Sunucudan spesifik bir hata mesajı gelmiş olabilir.
      // print(e.response?.data);
      return false;
    }
  }
}
