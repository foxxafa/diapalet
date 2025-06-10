// lib/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
// Projenizdeki doğru entity import yollarını kullandığınızdan emin olun.
import '../../domain/entities/transfer_operation_header.dart';
import '../../domain/entities/transfer_item_detail.dart';
import '../../domain/entities/product_item.dart';
import '../../domain/entities/assignment_mode.dart';
import '../../domain/entities/pallet_item.dart';
import '../../domain/entities/box_item.dart';
import '../../../../core/network/api_config.dart';

abstract class PalletAssignmentRemoteDataSource {
  Future<String> createNewPallet(String locationId);
  Future<bool> assignItemsToPallet(String palletId, List<PalletItem> items);
  Future<bool> sendTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<String>> fetchSourceLocations();
  Future<List<String>> fetchTargetLocations();
  Future<List<String>> fetchContainerIds(String location, AssignmentMode mode);
  Future<List<ProductItem>> fetchContainerContents(String containerId, AssignmentMode mode);
  Future<List<BoxItem>> fetchBoxesAtLocation(String location);
}

class PalletAssignmentRemoteDataSourceImpl implements PalletAssignmentRemoteDataSource {
  final Dio _dio;

  // **GÜNCELLENDİ:** Base URL, yerel ağdaki Flask sunucusunu işaret edecek şekilde değiştirildi.
  // "YOUR_PC_IP_ADDRESS" kısmını kendi bilgisayarınızın IP adresi ile değiştirin.
  PalletAssignmentRemoteDataSourceImpl({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  @override
  Future<String> createNewPallet(String locationId) async {
    debugPrint("API: Creating a new pallet at location: $locationId on remote...");
    try {
      final response = await _dio.post('/pallets', data: {'location_id': locationId});

      if (response.statusCode == 201 && response.data['pallet_id'] != null) {
        final newPalletId = response.data['pallet_id'].toString(); // Gelen ID int olabilir, string'e çevir.
        debugPrint("API: Pallet created with ID: $newPalletId");
        return newPalletId;
      } else {
        throw Exception('Failed to create pallet. Invalid response from server.');
      }
    } on DioException catch (e) {
      debugPrint("API Error creating pallet: ${e.message}");
      debugPrint("API Error response: ${e.response?.data}");
      rethrow;
    }
  }

  @override
  Future<bool> assignItemsToPallet(String palletId, List<PalletItem> items) async {
    debugPrint("API: Assigning ${items.length} items to pallet ID: $palletId on remote...");
    try {
      final payload = {
        'items': items.map((item) => item.toJson()).toList(),
      };
      final response = await _dio.post('/pallets/$palletId/items', data: payload);

      if (response.statusCode == 200) {
        debugPrint("API: Items assigned to pallet successfully.");
        return true;
      } else {
        debugPrint("API: Failed to assign items to pallet. Status: ${response.statusCode}, Body: ${response.data}");
        return false;
      }
    } on DioException catch (e) {
      debugPrint("API Error assigning items to pallet: ${e.message}");
      debugPrint("API Error response: ${e.response?.data}");
      return false;
    }
  }

  // --- Mock'tan Gerçek API'ye Çevrilen Diğer Fonksiyonlar ---

  @override
  Future<List<String>> fetchSourceLocations() async {
    debugPrint("API: Fetching source locations from API...");
    try {
      final response = await _dio.get('/locations/source');
      if (response.statusCode == 200 && response.data is List) {
        return List<String>.from(response.data.map((item) => item['name'].toString()));
      }
      throw Exception('Failed to load source locations');
    } on DioException catch (e) {
      debugPrint("API Error fetching source locations: ${e.message}");
      rethrow;
    }
  }

  @override
  Future<List<String>> fetchTargetLocations() async {
    debugPrint("API: Fetching target locations from API...");
    try {
      final response = await _dio.get('/locations/target');
      if (response.statusCode == 200 && response.data is List) {
        return List<String>.from(response.data.map((item) => item['name'].toString()));
      }
      throw Exception('Failed to load target locations');
    } on DioException catch (e) {
      debugPrint("API Error fetching target locations: ${e.message}");
      rethrow;
    }
  }

  @override
  Future<List<String>> fetchContainerIds(String location, AssignmentMode mode) async {
    debugPrint("API: Fetching container IDs at $location for ${mode.displayName} from API...");
    try {
      final encodedLocation = Uri.encodeComponent(location);
      final response = await _dio.get('/containers/$encodedLocation/ids', queryParameters: {'mode': mode.name});
      if (response.statusCode == 200 && response.data is List) {
        // Gelen ID'ler integer (box mode) veya string (pallet mode) olabilir.
        // Hepsini string'e çevirerek统一laştırıyoruz.
        return (response.data as List).map((id) => id.toString()).toList();
      }
      throw Exception('Failed to load container IDs');
    } on DioException catch (e) {
      debugPrint("API Error fetching container IDs: ${e.message}");
      rethrow;
    }
  }

  @override
  Future<List<ProductItem>> fetchContainerContents(String containerId, AssignmentMode mode) async {
    debugPrint("API: Fetching contents for ${mode.displayName} ID: $containerId from API...");
    try {
      final encodedContainer = Uri.encodeComponent(containerId);
      final response = await _dio.get('/containers/$encodedContainer/contents', queryParameters: {'mode': mode.name});
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List).map((json) => ProductItem.fromJson(json)).toList();
      }
      return []; // Boş liste dönmek daha güvenli
    } on DioException catch (e) {
      debugPrint("API Error fetching container contents: ${e.message}");
      return [];
    }
  }

  @override
  Future<bool> sendTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    debugPrint("API: Sending transfer operation to API...");

    // Header'ı sunucunun beklediği alan adlarıyla dönüştür.
    final headerMap = {
      // Flask backend expects exactly these keys
      'operation_type': header.operationType.name,          // pallet | box
      'source_location': header.sourceLocation,             // Kaynak lokasyon adı
      'target_location': header.targetLocation,             // Hedef lokasyon adı
      'pallet_id': header.containerId,                      // Palet barkodu veya ürün ID'si
      // Backend'imiz employee_id bekliyor ancak mobil tarafta henüz kullanıcı yönetimi yok.
      // Şimdilik sabit bir değer (1) gönderiyoruz. Gerektiğinde burada gerçek kullanıcı ID'si kullanılabilir.
      'employee_id': 1,
      'transfer_date': header.transferDate.toIso8601String(),
    };

    // Her iki mod (pallet & box) için de items listesi gönderiyoruz.
    // Palet transferinde sunucu ürün listesini yok saysa bile boş liste gönderilirse
    // "Invalid payload" hatasını önleriz.
    final itemsList = items.map((item) => {
      // Flask tarafında 'product_id' INT olarak bekleniyor.
      'product_id': int.tryParse(item.productId) ?? item.productId,
      'quantity': item.quantity,
    }).toList();

    final payload = {
      'header': headerMap,
      'items': itemsList,
    };

    debugPrint("API Payload => $payload");

    try {
      final response = await _dio.post('/transfers', data: payload);
      final success = response.statusCode == 200 || response.statusCode == 201;
      debugPrint("API: Transfer operation sent. Status: ${response.statusCode}");
      return success;
    } on DioException catch (e) {
      debugPrint("API Error sending transfer operation: ${e.message}");
      debugPrint("API Error response: ${e.response?.data}");
      return false;
    }
  }

  @override
  Future<List<BoxItem>> fetchBoxesAtLocation(String location) async {
    try {
      final ids = await fetchContainerIds(location, AssignmentMode.box);
      final List<BoxItem> boxes = [];
      for (final id in ids) {
        final encodedId = Uri.encodeComponent(id);
        final response = await _dio.get('/containers/$encodedId/contents', queryParameters: {'mode': AssignmentMode.box.name});
        if (response.statusCode != 200 || response.data is! List) continue;

        // Find the row that matches the requested location
        final List<dynamic> rows = response.data;
        final rowForLocation = rows.firstWhere(
          (r) => (r['locationName'] ?? '').toString() == location,
          orElse: () => rows.first,
        );

        final qtyVal = rowForLocation['quantity'];
        int qty;
        if (qtyVal is int) {
          qty = qtyVal;
        } else if (qtyVal is double) {
          qty = qtyVal.round();
        } else if (qtyVal is String) {
          qty = double.tryParse(qtyVal)?.round() ?? 0;
        } else {
          qty = 0;
        }

        boxes.add(BoxItem(
          boxId: int.tryParse(id) ?? 0,
          productId: (rowForLocation['productId'] ?? id).toString(),
          productName: (rowForLocation['productName'] ?? '').toString(),
          productCode: (rowForLocation['productCode'] ?? '').toString(),
          quantity: qty,
        ));
      }
      return boxes;
    } catch (e) {
      debugPrint("API Error fetchBoxesAtLocation: $e");
      rethrow;
    }
  }
}
