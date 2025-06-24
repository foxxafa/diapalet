// lib/features/auth/domain/repositories/auth_repository.dart

/// Kullanıcı kimlik doğrulama işlemlerini yöneten soyut sınıf.
abstract class AuthRepository {
  Future<Map<String, dynamic>?> login(String username, String password);

  // GÜNCELLEME: Çıkış fonksiyonu ekleniyor.
  Future<void> logout();
}