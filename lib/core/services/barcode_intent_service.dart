import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:receive_intent/receive_intent.dart';
import 'dart:io';


/// *************************
/// Barkod Intent Servisi
/// *************************
class BarcodeIntentService {
  static const _supportedActions = {
    'unitech.scanservice.data', // Unitech
    'com.symbol.datawedge.data.ACTION', // Zebra
    'com.honeywell.decode.intent.action.DECODE_EVENT', // Honeywell
    'com.datalogic.decodewedge.decode_action', // Datalogic
    'nlscan.action.SCANNER_RESULT', // Newland
    'android.intent.action.SEND', // Paylaşılan metin
  };

  static const _payloadKeys = [
    'text', // Unitech
    'com.symbol.datawedge.data_string',
    'com.honeywell.decode.intent.extra.DATA_STRING',
    'nlscan_code',
    'scannerdata',
    'barcode_data',
    'barcode',
    'data',
    'android.intent.extra.TEXT',
  ];

  /// Sürekli dinleyen yayın.
  Stream<String> get stream => ReceiveIntent.receivedIntentStream
      .where((intent) =>
          intent != null && _supportedActions.contains(intent.action) && !_isFromPayShare(intent))
      .map(_extractBarcode)
      .where((code) => code != null)
      .cast<String>();

  /// Uygulama ilk açılırken gelen Intent'i getirir.
  Future<String?> getInitialBarcode() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    final intent = await ReceiveIntent.getInitialIntent();
    if (intent == null ||
        !_supportedActions.contains(intent.action) ||
        _isFromPayShare(intent)) {
      return null;
    }
    return _extractBarcode(intent);
  }

  // Paycell, Pay gibi uygulamalardan "Paylaş" yapıldığında gelen intent'leri filtrele
  static bool _isFromPayShare(Intent intent) {
    return intent.extra?['android.intent.extra.SUBJECT'] != null;
  }


  /// Ortak veri çıkarıcı
  String? _extractBarcode(Intent? intent) {
    if (intent == null) return null;
    for (final key in _payloadKeys) {
      final value = intent.extra?[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.replaceAll(RegExp(r'[\r\n\t]'), '').trim();
      }
    }
    return null;
  }
} 