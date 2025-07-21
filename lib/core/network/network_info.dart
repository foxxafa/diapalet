// core/network/network_info.dart
import 'package:connectivity_plus/connectivity_plus.dart';

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
    return !result.contains(ConnectivityResult.none);
  }

  @override
  Stream<bool> get onConnectivityChanged {
    return connectivity.onConnectivityChanged.map((List<ConnectivityResult> result) {
      return !result.contains(ConnectivityResult.none);
    });
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
