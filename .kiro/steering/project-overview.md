# Diapalet - Mobil Depo Yönetim Sistemi

## Proje Hakkında
Diapalet, Flutter ile geliştirilmiş Android ve iOS destekli bir mobil depo yönetim sistemi uygulamasıdır. Depo operasyonlarını kolaylaştırmak ve verimliliği artırmak için tasarlanmıştır.

## Ana Özellikler
- **Kullanıcı Kimlik Doğrulama:** Güvenli e-posta ve şifre ile giriş
- **Mal Kabul:** Satın alma siparişlerini listeleme, QR kod okuma ile ürün tanıma
- **Envanter Transferi:** Sipariş bazlı ve serbest transfer işlemleri
- **Çevrimdışı Desteği:** İnternet bağlantısı olmadan çalışma ve otomatik senkronizasyon
- **Çoklu Dil Desteği:** Türkçe ve İngilizce
- **Dinamik Tema:** Açık/Koyu mod desteği

## Teknoloji Yığını
- **Frontend:** Flutter (v3.x.x)
- **Backend:** PHP (Yii Framework)
- **Mobil Veritabanı:** SQLite
- **State Management:** Provider
- **Mimari:** Feature-based (Özellik bazlı) mimari

## Temel Paketler
- provider (State Management)
- easy_localization (Çoklu dil)
- sqflite (SQLite veritabanı)
- mobile_scanner (QR kod okuma)
- dio, http (HTTP istekleri)
- flutter_form_builder (Form yönetimi)
- rxdart (Asenkron programlama)