import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:receive_intent/receive_intent.dart';
import 'dart:io';


/// *************************
/// Barkod Intent Servisi
/// *************************
class BarcodeIntentService {
  BarcodeIntentService._privateConstructor();
  static final BarcodeIntentService _instance = BarcodeIntentService._privateConstructor();

  factory BarcodeIntentService() {
    return _instance;
  }

  StreamController<String>? _controller;
  StreamSubscription<Intent?>? _intentSubscription;
  bool _isListening = false;

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

  Stream<String> get stream {
    if (_controller == null || _controller!.isClosed) {
      _controller = StreamController<String>.broadcast();
      _startListening();
    }
    return _controller!.stream;
  }

  void _startListening() {
    if (_isListening || kIsWeb || !Platform.isAndroid) return;

    _isListening = true;
    _intentSubscription = ReceiveIntent.receivedIntentStream
        .where((intent) =>
            intent != null &&
            _supportedActions.contains(intent.action) &&
            !_isFromPayShare(intent))
        .listen(
      (intent) {
        final code = _extractBarcode(intent);
        if (code != null && code.isNotEmpty) {
          if (_controller != null && !_controller!.isClosed) {
            _controller!.add(code);
          }
        }
      },
      onError: (e) {
        if (_controller != null && !_controller!.isClosed) {
          _controller!.addError(e);
        }
      },
      onDone: () {
        _stopListening();
      },
    );
  }

  void dispose() {
    _stopListening();
  }

  void _stopListening() {
    _intentSubscription?.cancel();
    _intentSubscription = null;
    _controller?.close();
    _controller = null;
    _isListening = false;
  }

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
        // GS1 verilerini ayrıştırmadan önce temizle.
        // Parantezleri, yaygın boşluk karakterlerini kaldır ve FNC1 ayırıcı
        // temsillerini standartlaştır (\x1d).
        return value
            .replaceAll(RegExp(r'[\r\n\t\(\)]'), '') // Parantezleri ve diğerlerini kaldır
            .replaceAll('[GS]', '\x1d') // Bazı tarayıcılar FNC1'i metin olarak gönderir
            .trim();
      }
    }
    return null;
  }
} 