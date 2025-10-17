import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// *************************
/// Ses Çalma Servisi
/// *************************
///
/// El terminali barkod okuma işlemlerinde ses bildirimi sağlar.
/// - Başarılı arama: boopk.mp3
/// - Başarısız arama: wrongk.mp3
class SoundService {
  SoundService._privateConstructor();
  static final SoundService _instance = SoundService._privateConstructor();

  factory SoundService() {
    return _instance;
  }

  final AudioPlayer _audioPlayer = AudioPlayer();

  /// Başarılı arama sesi çal (boopk.mp3)
  Future<void> playSuccessSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/boopk.mp3'));
      debugPrint('🔊 Başarılı arama sesi çalıyor: boopk.mp3');
    } catch (e) {
      debugPrint('❌ Ses çalma hatası (boopk.mp3): $e');
    }
  }

  /// Başarısız arama sesi çal (wrongk.mp3)
  Future<void> playErrorSound() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/wrongk.mp3'));
      debugPrint('🔊 Başarısız arama sesi çalıyor: wrongk.mp3');
    } catch (e) {
      debugPrint('❌ Ses çalma hatası (wrongk.mp3): $e');
    }
  }

  /// Servisi temizle
  void dispose() {
    _audioPlayer.dispose();
  }
}