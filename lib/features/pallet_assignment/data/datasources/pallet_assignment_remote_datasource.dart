// lib/features/pallet_assignment/data/datasources/pallet_assignment_remote_datasource.dart
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
// Corrected entity imports
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_operation_header.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/transfer_item_detail.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/product_item.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/assignment_mode.dart';
import 'package:diapalet/features/pallet_assignment/domain/entities/pallet_item.dart';

abstract class PalletAssignmentRemoteDataSource {
  /// **YENİ: Mal kabul için yeni bir palet oluşturur.**
  /// Sunucu tarafında yeni bir palet kaydı oluşturur ve benzersiz ID'sini döner.
  /// Bu, 'mal_kabul_paletleri' gibi bir tabloya yeni bir satır ekler.
  Future<String> createNewPallet(String locationId);

  /// **YENİ: Belirtilen palete ürünler atar.**
  /// `items` listesindeki ürünleri `palletId` ile belirtilen palete ekler.
  /// Bu, 'mal_kabul_palet_icerik' gibi bir ilişki tablosuna kayıtlar ekler.
  Future<bool> assignItemsToPallet(String palletId, List<PalletItem> items);

  Future<bool> sendTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items);
  Future<List<String>> fetchSourceLocations();
  Future<List<String>> fetchTargetLocations();
  Future<List<String>> fetchContainerIds(String location, AssignmentMode mode);
  Future<List<ProductItem>> fetchContainerContents(String containerId, AssignmentMode mode);
// Future<void> updateContainerLocationOnApi(String containerId, String newLocation); // Example
}

class PalletAssignmentRemoteDataSourceImpl implements PalletAssignmentRemoteDataSource {
  final Dio _dio;

  PalletAssignmentRemoteDataSourceImpl({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: "https://api.rowhub.com/v1"));

  @override
  Future<String> createNewPallet(String locationId) async {
    debugPrint("API: Creating a new pallet at location: $locationId on remote...");
    try {
      final response = await _dio.post('/pallets', data: {'location_id': locationId});
      
      if (response.statusCode == 201 && response.data['pallet_id'] != null) {
        final newPalletId = response.data['pallet_id'];
        debugPrint("API: Pallet created with ID: $newPalletId");
        return newPalletId;
      } else {
        throw Exception('Failed to create pallet. Invalid response from server.');
      }
    } on DioError catch (e) {
      debugPrint("API Error creating pallet: $e");
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
        debugPrint("API: Failed to assign items to pallet. Status: ${response.statusCode}");
        return false;
      }
    } on DioError catch (e) {
      debugPrint("API Error assigning items to pallet: $e");
      return false;
    }
  }

  @override
  Future<bool> sendTransferOperation(TransferOperationHeader header, List<TransferItemDetail> items) async {
    debugPrint("API: Sending transfer operation id: ${header.id ?? 'NEW'} to API...");
    // For API, you might send header.toMap() and items.map((item) => item.toMap()).toList()
    // Ensure item.toMap() for API doesn't strictly require operationId if it's derived from header context
    debugPrint("API: Header: ${header.toMap()}");
    for (var item in items) {
      // For API, item.toMap() might be different or you might construct payload differently
      debugPrint("API: Item (productCode: ${item.productCode}, productName: ${item.productName}, quantity: ${item.quantity})");
    }
    await Future.delayed(const Duration(seconds: 1));
    debugPrint("API: Transfer operation sent successfully (mock).");
    return true;
  }

  @override
  Future<List<String>> fetchSourceLocations() async {
    debugPrint("API: Fetching source locations (mock)...");
    await Future.delayed(const Duration(milliseconds: 300));
    return ["API-SRC-LOC-ALPHA", "API-SRC-LOC-BETA", "API-SRC-WAREHOUSE-MAIN"];
  }

  @override
  Future<List<String>> fetchTargetLocations() async {
    debugPrint("API: Fetching target locations (mock)...");
    await Future.delayed(const Duration(milliseconds: 300));
    return ["API-TGT-LOC-X", "API-TGT-LOC-Y", "API-TGT-SHIPPING_DOCK"];
  }

  @override
  Future<List<String>> fetchContainerIds(String location, AssignmentMode mode) async {
    debugPrint("API: Fetching container IDs at $location for ${mode.displayName} (mock)...");
    await Future.delayed(const Duration(milliseconds: 300));
    return ["API-MOCK-ID-1", "API-MOCK-ID-2"];
  }

  @override
  Future<List<ProductItem>> fetchContainerContents(String containerId, AssignmentMode mode) async {
    debugPrint("API: Fetching contents for ${mode.displayName} ID: $containerId from API (mock)...");
    await Future.delayed(const Duration(milliseconds: 500));
    if (containerId == "API-PALET-001" && mode == AssignmentMode.palet) {
      return [
        const ProductItem(id: "api_prod_tv", name: "API Smart TV 55\"", productCode: "TV55SMART", currentQuantity: 10),
        const ProductItem(id: "api_prod_ph", name: "API Smartphone X", productCode: "PHONEX", currentQuantity: 25),
      ];
    } else if (containerId == "API-KUTU-A5" && mode == AssignmentMode.kutu) {
      return [
        const ProductItem(id: "api_prod_lp", name: "API Laptop Pro", productCode: "LAPTOPPRO", currentQuantity: 5),
      ];
    } else if (containerId == "EMPTY-API") {
      return [];
    }
    debugPrint("API: No specific mock content for $containerId and $mode, returning empty list.");
    return [];
  }
}
