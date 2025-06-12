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
    // If the list is not empty and does not contain 'none', we have a connection.
    return result.isNotEmpty && !result.contains(ConnectivityResult.none);
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
  Stream<bool> get onConnectivityChanged => Stream.value(_isConnected);
}
