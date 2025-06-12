// core/network/network_info.dart
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
  Stream<bool> get onConnectivityChanged;
}

class NetworkInfoImpl implements NetworkInfo {
  final Connectivity connectivity;

  NetworkInfoImpl(this.connectivity);

  @override
  Future<bool> get isConnected async {
    final result = await connectivity.checkConnectivity();
    return _hasConnection(result);
  }

  @override
  Stream<bool> get onConnectivityChanged {
    return connectivity.onConnectivityChanged.map(_hasConnection);
  }

  bool _hasConnection(List<ConnectivityResult> result) {
    return result.isNotEmpty && !result.contains(ConnectivityResult.none);
  }
}

/// Mock implementation for testing purposes
class MockNetworkInfo implements NetworkInfo {
  bool _isConnected;

  MockNetworkInfo(this._isConnected);

  void setConnectionStatus(bool isConnected) {
    _isConnected = isConnected;
  }

  @override
  Future<bool> get isConnected => Future.value(_isConnected);

  @override
  Stream<bool> get onConnectivityChanged => Stream.value(_isConnected);
}
