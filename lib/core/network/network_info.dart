// core/network/network_info.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
  Stream<ConnectivityResult> get onConnectivityChanged;
}

class NetworkInfoImpl implements NetworkInfo {
  final Connectivity connectivity;

  NetworkInfoImpl(this.connectivity);

  @override
  Stream<ConnectivityResult> get onConnectivityChanged => connectivity.onConnectivityChanged.map((results) => results.first);

  @override
  Future<bool> get isConnected async {
    try {
      final connectivityResult = await connectivity.checkConnectivity();
      // connectivity_plus v5.0.0 ve sonrası List<ConnectivityResult> döndürür.
      // Bu yüzden listenin istenen bağlantı türlerinden birini içerip içermediğini kontrol ediyoruz.
      if (connectivityResult.contains(ConnectivityResult.mobile) ||
          connectivityResult.contains(ConnectivityResult.wifi) ||
          connectivityResult.contains(ConnectivityResult.ethernet) ||
          connectivityResult.contains(ConnectivityResult.vpn) ||
          connectivityResult.contains(ConnectivityResult.other) ||
          // Fallback for older versions or unexpected single result (though less likely with v5+)
          (connectivityResult.isNotEmpty && !connectivityResult.contains(ConnectivityResult.none))) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error checking connectivity: $e");
      return false;
    }
  }
}

class MockNetworkInfoImpl implements NetworkInfo {
  bool _isConnected;

  MockNetworkInfoImpl(this._isConnected);

  void setConnectionStatus(bool status) {
    _isConnected = status;
  }

  @override
  Future<bool> get isConnected async => _isConnected;

  // Mock implementation for the stream
  @override
  Stream<ConnectivityResult> get onConnectivityChanged => Stream.value(_isConnected ? ConnectivityResult.wifi : ConnectivityResult.none);
}
