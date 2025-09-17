<?php

namespace app\controllers;

use Yii;
use yii\helpers\Json;

/**
 * WMSTelegramNotification - WMS sistemi için Telegram bildirimleri
 */
class WMSTelegramNotification
{
    // Telegram Bot Token ve Chat ID'ler (config'den alınabilir)
    const TELEGRAM_BOT_TOKEN = '8109565458:AAF_h964jxK_N7s0Ukea97-lG2_Usg5jVKA'; // WMS440301BOT
    const TELEGRAM_CHAT_ID = '-1003079176188'; // 44.03.01 grup ID'si (supergroup)

    /**
     * Telegram üzerinden yöneticilere bildirim gönder
     */
    public static function sendNotification($subject, $message, $data = [])
    {
        // Production kontrolü kaldırıldı - Test için aktif
        // if (YII_ENV !== 'prod') {
        //     Yii::info("Telegram notification (DEV): $subject - $message", __METHOD__);
        //     return true;
        // }

        try {
            $botToken = Yii::$app->params['telegramBotToken'] ?? self::TELEGRAM_BOT_TOKEN;
            $chatId = Yii::$app->params['telegramChatId'] ?? self::TELEGRAM_CHAT_ID;

            if (empty($botToken) || empty($chatId)) {
                Yii::warning('Telegram bot token veya chat ID tanımlı değil', __METHOD__);
                return false;
            }

            // Mesaj formatla
            $formattedMessage = self::formatMessage($subject, $message, $data);

            // Telegram API'ye gönder
            $url = "https://api.telegram.org/bot{$botToken}/sendMessage";

            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, [
                'chat_id' => $chatId,
                'text' => $formattedMessage,
                'parse_mode' => 'HTML',
                'disable_web_page_preview' => true
            ]);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);

            $result = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curlError = curl_error($ch);
            curl_close($ch);

            // Debug için detaylı log
            Yii::info("Telegram API Response - HTTP: $httpCode, Result: $result, Error: $curlError", __METHOD__);

            if ($httpCode !== 200) {
                Yii::error("Telegram API hatası: HTTP $httpCode - $result - CURL Error: $curlError", __METHOD__);

                // Response'u decode et ve hata mesajını al
                $responseData = json_decode($result, true);
                if (isset($responseData['description'])) {
                    Yii::error("Telegram Error Description: " . $responseData['description'], __METHOD__);
                }

                return false;
            }

            return true;
        } catch (\Exception $e) {
            Yii::error("Telegram bildirim hatası: " . $e->getMessage(), __METHOD__);
            return false;
        }
    }

    /**
     * Telegram mesajını formatla
     */
    private static function formatMessage($subject, $message, $data = [])
    {
        $text = "<b>⚠️ {$subject}</b>\n\n";
        $text .= "{$message}\n";

        if (!empty($data)) {
            $text .= "\n<b>📊 Detaylar:</b>\n";
            foreach ($data as $key => $value) {
                if (is_array($value) || is_object($value)) {
                    $value = Json::encode($value);
                }
                $text .= "• <b>{$key}:</b> {$value}\n";
            }
        }

        $text .= "\n<i>🕐 " . date('Y-m-d H:i:s') . "</i>";

        return $text;
    }

    /**
     * Kritik mal kabul hatası bildirimi
     */
    public static function notifyGoodsReceiptError($employeeName, $orderId, $errorMessage, $details = [])
    {
        // Aynı hata için tekrar bildirim göndermeyi önle
        $notificationKey = "goods_receipt_error_{$orderId}_{$employeeName}";

        // Cache veya session'da bu bildirimin daha önce gönderilip gönderilmediğini kontrol et
        $cache = Yii::$app->cache;
        if ($cache) {
            $cacheKey = "telegram_notification_" . md5($notificationKey . $errorMessage);
            if ($cache->exists($cacheKey)) {
                Yii::info("Telegram notification already sent for: $notificationKey", __METHOD__);
                return true; // Zaten gönderilmiş, tekrar gönderme
            }

            // Cache'e kaydet - 1 saat boyunca aynı hata için tekrar gönderme
            $cache->set($cacheKey, true, 3600);
        }

        $subject = "MAL KABUL HATASI";
        $message = "Çalışan <b>{$employeeName}</b> sipariş <b>#{$orderId}</b> için mal kabul yapmaya çalıştı ancak başarısız oldu.";

        $data = array_merge([
            'Hata' => $errorMessage,
            'Çalışan' => $employeeName,
            'Sipariş' => "#$orderId",
            'Zaman' => date('Y-m-d H:i:s'),
        ], $details);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Transfer hatası bildirimi
     */
    public static function notifyTransferError($employeeName, $errorMessage, $details = [])
    {
        // Aynı hata için tekrar bildirim göndermeyi önle
        $notificationKey = "transfer_error_{$employeeName}_" . md5($errorMessage);

        // Cache kontrolü
        $cache = Yii::$app->cache;
        if ($cache) {
            $cacheKey = "telegram_notification_" . md5($notificationKey);
            if ($cache->exists($cacheKey)) {
                Yii::info("Telegram notification already sent for: $notificationKey", __METHOD__);
                return true;
            }
            // 30 dakika boyunca aynı hata için tekrar gönderme
            $cache->set($cacheKey, true, 1800);
        }

        $subject = "⚠️ TRANSFER HATASI";
        $message = "Çalışan <b>{$employeeName}</b> transfer işlemi sırasında hata aldı.";

        $data = array_merge([
            'Hata' => $errorMessage,
            'Çalışan' => $employeeName,
            'Zaman' => date('Y-m-d H:i:s')
        ], $details);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Kritik sistem hatası bildirimi
     */
    public static function notifyCriticalError($errorType, $errorMessage, $details = [])
    {
        $subject = "🚨 KRİTİK SİSTEM HATASI";
        $message = "WMS sisteminde kritik bir hata oluştu: <b>{$errorType}</b>";

        $data = array_merge([
            'Hata Tipi' => $errorType,
            'Hata Mesajı' => $errorMessage,
            'Zaman' => date('Y-m-d H:i:s'),
            'Sunucu' => gethostname() ?? 'Unknown'
        ], $details);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Başarılı transfer bildirimi (Büyük transferler için)
     */
    public static function notifySuccessfulTransfer($employeeName, $transferDetails = [])
    {
        // Sadece büyük transferler için bildirim gönder
        $quantity = $transferDetails['Miktar'] ?? 0;
        if ($quantity < 100) { // 100'den az ürün için bildirim gönderme
            return true;
        }

        $subject = "✅ BÜYÜK TRANSFER TAMAMLANDI";
        $message = "Çalışan <b>{$employeeName}</b> büyük bir transfer işlemi tamamladı.";

        $data = array_merge([
            'Çalışan' => $employeeName,
            'Zaman' => date('Y-m-d H:i:s')
        ], $transferDetails);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Stok uyarısı bildirimi
     */
    public static function notifyLowStock($productName, $stockCode, $currentQuantity, $minQuantity, $warehouseCode)
    {
        // Cache kontrolü - her ürün için günde bir kez bildirim
        $notificationKey = "low_stock_{$stockCode}_{$warehouseCode}";
        $cache = Yii::$app->cache;
        if ($cache) {
            $cacheKey = "telegram_notification_" . md5($notificationKey);
            if ($cache->exists($cacheKey)) {
                return true;
            }
            // 24 saat boyunca aynı ürün için tekrar gönderme
            $cache->set($cacheKey, true, 86400);
        }

        $subject = "📉 DÜŞÜK STOK UYARISI";
        $message = "Ürün <b>{$productName}</b> için stok kritik seviyede.";

        $data = [
            'Ürün' => $productName,
            'Stok Kodu' => $stockCode,
            'Mevcut Miktar' => $currentQuantity,
            'Minimum Miktar' => $minQuantity,
            'Depo' => $warehouseCode,
            'Zaman' => date('Y-m-d H:i:s')
        ];

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Sipariş kapama hatası bildirimi
     */
    public static function notifyOrderCloseError($employeeName, $orderId, $errorMessage, $details = [])
    {
        $subject = "⛔ SİPARİŞ KAPAMA HATASI";
        $message = "Çalışan <b>{$employeeName}</b> sipariş <b>#{$orderId}</b> kapatılırken hata oluştu.";

        $data = array_merge([
            'Hata' => $errorMessage,
            'Çalışan' => $employeeName,
            'Sipariş' => "#$orderId",
            'Zaman' => date('Y-m-d H:i:s')
        ], $details);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * DIA entegrasyon hatası bildirimi
     */
    public static function notifyDIAError($operation, $errorMessage, $details = [])
    {
        // Cache kontrolü - aynı işlem için 30 dakika içinde tekrar gönderme
        $notificationKey = "dia_error_{$operation}_" . md5($errorMessage);
        $cache = Yii::$app->cache;
        if ($cache) {
            $cacheKey = "telegram_notification_" . md5($notificationKey);
            if ($cache->exists($cacheKey)) {
                return true;
            }
            $cache->set($cacheKey, true, 1800);
        }

        $subject = "🔌 DIA ENTEGRASYON HATASI";
        $message = "DIA sistemi ile iletişimde hata: <b>{$operation}</b>";

        $data = array_merge([
            'İşlem' => $operation,
            'Hata' => $errorMessage,
            'Zaman' => date('Y-m-d H:i:s')
        ], $details);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Permanent error bildirimi (Kalıcı hatalar)
     */
    public static function notifyPermanentError($employeeName, $operation, $errorMessage, $details = [])
    {
        $subject = "🔴 KALICI HATA";
        $message = "<b>{$operation}</b> işlemi kalıcı bir hata nedeniyle başarısız oldu.";

        $data = array_merge([
            'İşlem' => $operation,
            'Hata' => $errorMessage,
            'Çalışan' => $employeeName,
            'Durum' => 'Bu işlem tekrar denenmeyecek',
            'Zaman' => date('Y-m-d H:i:s')
        ], $details);

        return self::sendNotification($subject, $message, $data);
    }

    /**
     * Grup ID'sini almak için test metodu
     * Grup'ta "/start" yazdıktan sonra bu metodu çalıştırın
     */
    public static function getGroupId()
    {
        $botToken = self::TELEGRAM_BOT_TOKEN;
        $url = "https://api.telegram.org/bot{$botToken}/getUpdates";

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);

        $result = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode === 200) {
            $data = json_decode($result, true);
            if (!empty($data['result'])) {
                foreach ($data['result'] as $update) {
                    if (isset($update['message']['chat']['id'])) {
                        $chatId = $update['message']['chat']['id'];
                        $chatTitle = $update['message']['chat']['title'] ?? 'Private';
                        Yii::info("Chat found - ID: {$chatId}, Title: {$chatTitle}", __METHOD__);

                        // Test mesajı gönder
                        self::sendTestMessage($chatId);
                    }
                }
            }
            return $data;
        }

        return false;
    }

    /**
     * Test mesajı gönder
     */
    public static function sendTestMessage($chatId = null)
    {
        if ($chatId === null) {
            $chatId = self::TELEGRAM_CHAT_ID;
        }

        $botToken = self::TELEGRAM_BOT_TOKEN;
        $url = "https://api.telegram.org/bot{$botToken}/sendMessage";

        $message = "🎉 <b>WMS Bot Bağlantısı Başarılı!</b>\n\n";
        $message .= "✅ Bot başarıyla gruba eklendi.\n";
        $message .= "📍 Grup ID: <code>{$chatId}</code>\n";
        $message .= "🤖 Bot: @WMS440301BOT\n";
        $message .= "🔧 Sistem: DIAPALET WMS\n\n";
        $message .= "Bu grup artık kritik WMS hatalarında bildirim alacak.";

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, [
            'chat_id' => $chatId,
            'text' => $message,
            'parse_mode' => 'HTML'
        ]);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);

        $result = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        return $httpCode === 200;
    }
}