// lib/features/auth/domain/repositories/auth_repository.dart

/// Kullanıcı kimlik doğrulama işlemlerini yöneten soyut sınıf.
abstract class AuthRepository {
  /// Kullanıcı adı ve şifre ile giriş yapmayı dener.
  ///
  /// Cihazda internet bağlantısı varsa API üzerinden, yoksa yerel veritabanından
  /// kimlik doğrulaması yapar.
  /// Başarılı olursa `true` döner, olmazsa hata fırlatır.
  Future<bool> login(String username, String password);
}
