// lib/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/pallet_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/box_item.dart';
import 'package:diapalet/core/network/api_config.dart';
import 'package:diapalet/features/goods_receiving/domain/entities/location_info.dart';

abstract class PalletAssignmentRemoteDataSource {
  Future<String> createNewPallet(String locationId);
  Future<bool> assignItemsToPallet(String palletId, List<PalletItem> items);
  Future<bool> sendTransferOperation(
    TransferOperationHeader header,
    List<TransferItemDetail> items, {
    required String sourceLocationName,
    required String targetLocationName,
  });
  Future<List<LocationInfo>> fetchSourceLocations();
  Future<List<LocationInfo>> fetchTargetLocations();
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
  Future<List<LocationInfo>> fetchSourceLocations() async {
    debugPrint("API: Fetching source locations from API...");
    try {
      final response = await _dio.get('/locations/source');
      if (response.statusCode == 200 && response.data is List) {
        final locations = (response.data as List)
            .map((item) => LocationInfo.fromMap(item as Map<String, dynamic>))
            .toList();
        return locations;
      }
      throw Exception('Failed to load source locations');
    } on DioException catch (e) {
      debugPrint("API Error fetching source locations: ${e.message}");
      rethrow;
    }
  }

  @override
  Future<List<LocationInfo>> fetchTargetLocations() async {
    debugPrint("API: Fetching target locations from API...");
    try {
      final response = await _dio.get('/locations/target');
      if (response.statusCode == 200 && response.data is List) {
        final locations = (response.data as List)
            .map((item) => LocationInfo.fromMap(item as Map<String, dynamic>))
            .toList();
        return locations;
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
  Future<bool> sendTransferOperation(
    TransferOperationHeader header,
    List<TransferItemDetail> items, {
    required String sourceLocationName,
    required String targetLocationName,
  }) async {
    // Prepare the payload according to the CURRENT server.py structure
    final payload = {
      "header": {
        "operation_type": header.operationType == AssignmentMode.pallet ? 'pallet_transfer' : 'box_transfer',
        "source_location": sourceLocationName, // Use name as expected by current server
        "target_location": targetLocationName, // Use name as expected by current server
        "pallet_id": header.containerId,
        "employee_id": 1, // Example employee ID
        "transfer_date": header.transferDate.toIso8601String(),
      },
      "items": items.map((item) => {
        "product_id": item.productId,
        "quantity": item.quantity,
      }).toList(),
    };

    try {
      // NOTE: The endpoint is /v1/transfers, not just /transfers
      final response = await _dio.post('/v1/transfers', data: payload);
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
    debugPrint("API: Fetching boxes at location: $location");
    try {
      final encodedLocation = Uri.encodeComponent(location);
      // Directly call the endpoint that returns box details for a location.
      final response = await _dio.get('/containers/$encodedLocation/ids', queryParameters: {'mode': 'box'});
      
      if (response.statusCode == 200 && response.data is List) {
        // The server for ?mode=box returns a list of objects with product details.
        // We map this directly to our BoxItem entity.
        final boxes = (response.data as List).map((item) {
          final map = item as Map<String, dynamic>;
          // The server query for boxes groups by product, so we use productId as the unique boxId for the dropdown.
          return BoxItem.fromMap({
            ...map,
            'box_id': map['productId'], 
          });
        }).toList();
        return boxes;
      } else {
        throw Exception('Failed to load boxes. Status: ${response.statusCode}');
      }
    } on DioException catch (e) {
      debugPrint("API Error fetching boxes: ${e.message}");
      rethrow;
    }
  }
}
