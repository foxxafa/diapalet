// core/network/network_info.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
}

class NetworkInfoImpl implements NetworkInfo {
  final Connectivity connectivity;

  NetworkInfoImpl(this.connectivity);

  @override
  Future<bool> get isConnected async {
    try {
      final connectivityResult = await connectivity.checkConnectivity();
      // connectivity_plus v5.0.0 ve sonrası tek bir sonuç döndürür.
      // Bu yüzden doğrudan karşılaştırma yapıyoruz.
      if (connectivityResult == ConnectivityResult.mobile ||
          connectivityResult == ConnectivityResult.wifi ||
          connectivityResult == ConnectivityResult.ethernet ||
          connectivityResult == ConnectivityResult.vpn ||
          connectivityResult == ConnectivityResult.other) { // 'other' da eklendi
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
}
