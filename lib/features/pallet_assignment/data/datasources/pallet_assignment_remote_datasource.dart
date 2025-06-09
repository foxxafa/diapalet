// lib/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
// Projenizdeki doğru entity import yollarını kullandığınızdan emin olun.
import '../../domain/entities/transfer_operation_header.dart';
import '../../domain/entities/transfer_item_detail.dart';
import '../../domain/entities/product_item.dart';
import '../../domain/entities/assignment_mode.dart';
import '../../domain/entities/pallet_item.dart';
import '../../../../core/network/api_config.dart';

abstract class PalletAssignmentRemoteDataSource {
  Future<String> createNewPallet(String locationId);
  Future<bool> assignItemsToPallet(String palletId, List<PalletItem> items);
  Future<bool> sendTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<String>> fetchSourceLocations();
  Future<List<String>> fetchTargetLocations();
  Future<List<String>> fetchContainerIds(String location, AssignmentMode mode);
  Future<List<ProductItem>> fetchContainerContents(String containerId, AssignmentMode mode);
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
      final response = await _dio.post('pallets', data: {'location_id': locationId});

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
      final response = await _dio.post('pallets/$palletId/items', data: payload);

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
      final response = await _dio.get('locations/source');
      if (response.statusCode == 200 && response.data is List) {
        return List<String>.from(response.data);
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
      final response = await _dio.get('locations/target');
      if (response.statusCode == 200 && response.data is List) {
        return List<String>.from(response.data);
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
      final response = await _dio.get('containers/$location/ids', queryParameters: {'mode': mode.name});
      if (response.statusCode == 200 && response.data is List) {
        return List<String>.from(response.data);
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
      final response = await _dio.get('containers/$containerId/contents', queryParameters: {'mode': mode.name});
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
    try {
      final payload = {
        'header': header.toMap(),
        'items': items.map((item) => item.toMap()).toList(),
      };
      final response = await _dio.post('transfers', data: payload);
      return response.statusCode == 200;
    } on DioException catch (e) {
      debugPrint("API Error sending transfer operation: ${e.message}");
      return false;
    }
  }
}
