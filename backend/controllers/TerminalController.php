<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;
use yii\web\Response;
use yii\db\Transaction;
use yii\db\Query;
use app\components\DepoComponent;
use app\components\Dia;
use app\models\GoodsReceipts;
use app\models\GoodsReceiptItems;

class TerminalController extends Controller
{
    public function beforeAction($action)
    {
        Yii::$app->response->format = Response::FORMAT_JSON;
        $this->enableCsrfValidation = false;

        // HATA DÜZELTMESİ: Veritabanı timezone'ını UTC'ye ayarla (global uyumluluk için)
        Yii::$app->db->createCommand("SET time_zone = '+00:00'")->execute();

        // Test endpoint'leri ve telegram-log-file için API key kontrolünü atla
        $publicActions = ['login', 'health-check', 'sync-shelfs', 'test-telegram', 'test-telegram-error', 'test-telegram-debug', 'test-telegram-updates', 'telegram-log-file'];

        if (!in_array($action->id, $publicActions)) {
            $this->checkApiKey();
        }

        return parent::beforeAction($action);
    }

    private function logToFile($message, $level = 'INFO')
    {
        $logDir = Yii::getAlias('@runtime/logs');
        if (!is_dir($logDir)) {
            mkdir($logDir, 0755, true);
        }
        $logFile = $logDir . '/terminal_debug.log';
        $timestamp = date('Y-m-d H:i:s');
        $logEntry = "[$timestamp] [$level] $message" . PHP_EOL;
        file_put_contents($logFile, $logEntry, FILE_APPEND | LOCK_EX);
    }

    private function handleError(\Exception $e, $context = '', $statusCode = 500)
    {
        $message = $context ? "$context: {$e->getMessage()}" : $e->getMessage();
        $this->logToFile($message . "\nTrace: " . $e->getTraceAsString(), 'ERROR');
        Yii::$app->response->statusCode = $statusCode;
        return $this->asJson(['status' => $statusCode, 'message' => $message]);
    }

    private function handleDbError(\Exception $e, $context = '', $statusCode = 500)
    {
        $message = $context ? "$context: {$e->getMessage()}" : "Veritabanı hatası: {$e->getMessage()}";
        $this->logToFile($message, 'ERROR');
        Yii::$app->response->statusCode = $statusCode;
        return $this->asJson(['status' => $statusCode, 'message' => 'Sunucu tarafında bir hata oluştu: ' . $e->getMessage()]);
    }

    private function errorResponse($message, $statusCode = 500)
    {
        Yii::$app->response->statusCode = $statusCode;
        return ['success' => false, 'error' => $message];
    }

    private function successResponse($data = [])
    {
        return $this->mergeArraysSafely(['success' => true], $data);
    }

    private function validateGoodsReceiptData($data)
    {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        
        if (!$this->areAllNotEmpty($header, $items, $header['employee_id'] ?? null)) {
            return 'Geçersiz mal kabul verisi.';
        }
        return null; // Valid
    }

    private function validateInventoryTransferData($data)
    {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        
        if (empty($header) || empty($items) || !isset($header['employee_id'], $header['target_location_id']) || !array_key_exists('source_location_id', $header)) {
            return 'Geçersiz transfer verisi.';
        }
        return null; // Valid
    }

    private function getCurrentUtcTimestamp()
    {
        return (new \DateTime('now', new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.u\Z');
    }

    /**
     * Convert ISO8601 datetime to MySQL datetime format
     * Converts: 2025-10-09T14:13:34.543910Z -> 2025-10-09 14:13:34
     */
    private function convertIso8601ToMysqlDatetime($iso8601String)
    {
        if (empty($iso8601String)) {
            $this->logToFile("Date conversion: empty input", 'DEBUG');
            return null;
        }

        try {
            // Parse ISO8601 string (supports both Z and timezone formats)
            $dt = new \DateTime($iso8601String);

            // KRITIK FIX: Always convert to UTC before storing in MySQL
            // Mobile sends dates with timezone info (e.g., +03:00), we must normalize to UTC
            $dt->setTimezone(new \DateTimeZone('UTC'));

            // Return MySQL datetime format (without microseconds)
            $mysqlFormat = $dt->format('Y-m-d H:i:s');
            $this->logToFile("Date conversion: {$iso8601String} -> {$mysqlFormat} (UTC)", 'DEBUG');
            return $mysqlFormat;
        } catch (\Exception $e) {
            $this->logToFile("Date conversion error: {$iso8601String} - {$e->getMessage()}", 'WARNING');
            return null;
        }
    }

    private function hasValidConditions($conditions)
    {
        return count($conditions) > 1;
    }

    private function mergeArraysSafely($primary, $secondary)
    {
        return array_merge($primary ?? [], $secondary ?? []);
    }

    private function isNotEmpty($value)
    {
        return !empty($value);
    }

    private function areAllNotEmpty(...$values)
    {
        foreach ($values as $value) {
            if (empty($value)) {
                return false;
            }
        }
        return true;
    }

    private function hasAnyData($array)
    {
        return !empty($array) && is_array($array);
    }

    private function getStokKoduByUrunKey($urunKey, $db)
    {
        return (new Query())
            ->select('StokKodu')
            ->from('urunler')
            ->where(['_key' => $urunKey])
            ->scalar($db);
    }

    private function getEmployeeIdsByWarehouseCode($warehouseCode)
    {
        return (new Query())
            ->select('id')
            ->from('employees')
            ->where(['warehouse_code' => $warehouseCode])
            ->column();
    }

    private function getWarehouseInfoById($warehouseId)
    {
        return (new Query())
            ->select(['id', 'warehouse_code', 'name', '_key'])
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->one();
    }

    private function getWarehouseCodeById($warehouseId)
    {
        return (new Query())
            ->select('warehouse_code')
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->scalar();
    }

    private function getJsonBody()
    {
        $rawBody = Yii::$app->request->getRawBody();
        $decoded = json_decode($rawBody, true);
        return is_array($decoded) ? $decoded : [];
    }

    private function checkApiKey()
    {
        $authHeader = Yii::$app->request->headers->get('Authorization');
        if ($authHeader === null || !preg_match('/^Bearer\s+(.+)$/', $authHeader, $matches)) {
            // DÜZELTME: echo yerine Yii2'nin standart exception'ı kullanıldı.
            // Bu, 'Headers already sent' hatasını önler.
            throw new \yii\web\UnauthorizedHttpException('Yetkisiz erişim: API anahtarı eksik veya geçersiz.');
        }
    }

    private function castNumericValues(array &$data, array $intKeys, array $floatKeys = [])
    {
        if (empty($data)) return;
        
        foreach ($data as &$row) {
            foreach ($intKeys as $key) {
                if (isset($row[$key])) $row[$key] = (int)$row[$key];
            }
            foreach ($floatKeys as $key) {
                if (isset($row[$key])) $row[$key] = (float)$row[$key];
            }
        }
    }

    private function applyStandardCasts(array &$data, $type = 'default')
    {
        if (empty($data)) return;
        
        switch ($type) {
            case 'urunler':
                $this->castNumericValues($data, ['id', 'aktif']);
                break;
            case 'tedarikci':
                $this->castNumericValues($data, ['id', 'Aktif']);
                break;
            case 'employees':
                $this->castNumericValues($data, ['id', 'is_active']);
                break;
            case 'shelfs':
                $this->castNumericValues($data, ['id', 'warehouse_id', 'is_active']);
                break;
            case 'inventory_stock':
                $this->castNumericValues($data, ['id', 'location_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);
                break;
            case 'goods_receipts':
                $this->castNumericValues($data, ['id', 'siparis_id', 'employee_id']);
                break;
            default:
                // Varsayılan cast işlemi yok
                break;
        }
    }

    /**
     * UUID v4 üretir
     */
    private function generateUuid()
    {
        // PHP 7.0+ için UUID v4 üretimi
        return sprintf('%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
            mt_rand(0, 0xffff), mt_rand(0, 0xffff),
            mt_rand(0, 0xffff),
            mt_rand(0, 0x0fff) | 0x4000,
            mt_rand(0, 0x3fff) | 0x8000,
            mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
        );
    }

    /**
     * Tek bir inventory_stock kaydının UUID'sini tombstone tablosuna kaydeder
     */
    private function logSingleDeletion($db, $stockId, $warehouseCode = null)
    {
        try {
            // Stock UUID'sini ve warehouse_code'u al
            $stockInfo = (new Query())
                ->select(['stock_uuid', 'warehouse_code'])
                ->from('inventory_stock')
                ->where(['id' => $stockId])
                ->one($db);
            
            if ($stockInfo && $stockInfo['stock_uuid']) {
                $db->createCommand()->insert('wms_tombstones', [
                    'stock_uuid' => $stockInfo['stock_uuid'],
                    'warehouse_code' => $warehouseCode ?: $stockInfo['warehouse_code'],
                    'deleted_at' => new \yii\db\Expression('NOW()')
                ])->execute();
                
                Yii::info("TOMBSTONE: Single deletion logged for UUID: {$stockInfo['stock_uuid']}", __METHOD__);
            }
        } catch (\Exception $e) {
            $this->logToFile("Tombstone logging failed for stock ID $stockId: " . $e->getMessage(), 'ERROR');
        }
    }

    public function actionLogin()
    {
        $params = $this->getJsonBody();
        $username = $params['username'] ?? null;
        $password = $params['password'] ?? null;

        if (!$username || !$password) {
            return $this->asJson(['status' => 400, 'message' => 'Kullanıcı adı ve şifre gereklidir.']);
        }

        try {
            // Rowhub formatında giriş sorgusu
            $userQuery = (new Query())
                ->select([
                    'e.id', 'e.first_name', 'e.last_name', 'e.username', 'e.role',
                    'e.warehouse_code',
                    'COALESCE(w.name, "Default Warehouse") as warehouse_name',
                    'COALESCE(w.receiving_mode, 2) as receiving_mode',
                    'e.branch_code',
                    'COALESCE(b.name, "Default Branch") as branch_name',
                    'COALESCE(b.id, 1) as branch_id'
                ])
                ->from(['e' => 'employees'])
                ->leftJoin(['w' => 'warehouses'], 'e.warehouse_code = w.warehouse_code')
                ->leftJoin(['b' => 'branches'], 'e.branch_code = b.branch_code')
                ->where(['e.username' => $username, 'e.password' => $password, 'e.is_active' => 1]);

            $user = $userQuery->one();

            if ($user) {
                // WMS rolü kontrolü - sadece WMS rolü olanlar giriş yapabilir
                if ($user['role'] !== 'WMS') {
                    return $this->asJson(['status' => 403, 'message' => 'Bu uygulamaya erişim yetkiniz bulunmamaktadır. Sadece WMS rolüne sahip kullanıcılar giriş yapabilir.']);
                }
                
                $apiKey = Yii::$app->security->generateRandomString();
                $userData = [
                    'id' => (int)$user['id'],
                    'first_name' => $user['first_name'],
                    'last_name' => $user['last_name'],
                    'username' => $user['username'],
                    'role' => $user['role'],
                    'warehouse_name' => $user['warehouse_name'],
                    'warehouse_code' => $user['warehouse_code'],
                    'receiving_mode' => (int)($user['receiving_mode'] ?? 2),
                    'branch_id' => (int)($user['branch_id'] ?? 1),
                    'branch_name' => $user['branch_name'],
                ];

                // Kullanıcının branch_code'una göre tüm warehouse'ları çek
                $branchCode = $user['branch_code'] ?? null;
                $warehouses = [];

                if ($branchCode) {
                    $warehouses = (new Query())
                        ->select(['warehouse_code', 'name', 'receiving_mode', 'id'])
                        ->from('warehouses')
                        ->where(['branch_code' => $branchCode])
                        ->all();

                    // Cast işlemleri
                    foreach ($warehouses as &$warehouse) {
                        $warehouse['id'] = (int)$warehouse['id'];
                        $warehouse['receiving_mode'] = (int)($warehouse['receiving_mode'] ?? 2);
                    }
                }

                return $this->asJson([
                    'status' => 200,
                    'message' => 'Giriş başarılı.',
                    'user' => $userData,
                    'apikey' => $apiKey,
                    'warehouses' => $warehouses
                ]);
            } else {
                return $this->asJson(['status' => 401, 'message' => 'Kullanıcı adı veya şifre hatalı.']);
            }
        } catch (\yii\db\Exception $e) {
            return $this->handleDbError($e, 'Login DB Hatası');
        } catch (\Exception $e) {
            return $this->handleError($e, 'Login Genel Hatası');
        }
    }

    public function actionSyncUpload()
    {
        // Log raw body for debugging
        $rawBody = Yii::$app->request->getRawBody();
        $this->logToFile("actionSyncUpload - Raw body length: " . strlen($rawBody), 'DEBUG');
        if (strlen($rawBody) < 5000) {
            $this->logToFile("actionSyncUpload - Raw body: " . $rawBody, 'DEBUG');
        } else {
            $this->logToFile("actionSyncUpload - Raw body (first 2000 chars): " . substr($rawBody, 0, 2000), 'DEBUG');
        }

        $payload = $this->getJsonBody();
        $this->logToFile("actionSyncUpload - Payload keys: " . json_encode(array_keys($payload)), 'DEBUG');
        $this->logToFile("actionSyncUpload - Operations count: " . count($payload['operations'] ?? []), 'DEBUG');

        $operations = $payload['operations'] ?? [];
        $db = Yii::$app->db;
        $results = [];

        if (empty($operations)) {
            return ['success' => true, 'results' => []];
        }

        // 🔧 YENİ YAKLŞIM: Her operasyon için AYRI transaction
        // Bu sayede bir operasyonun hatası diğerlerini etkilemez
        // İdempotency mekanizması düzgün çalışır (processed_requests kaydı korunur)

        foreach ($operations as $op) {
            $localId = $op['local_id'] ?? null;
            $idempotencyKey = $op['idempotency_key'] ?? null;

            if (!$localId || !$idempotencyKey) {
                // Kritik hata - tüm batch'i reddet
                $this->logToFile("Missing local_id or idempotency_key in operation", 'ERROR');
                Yii::$app->response->setStatusCode(400);
                return [
                    'success' => false,
                    'error' => "Tüm operasyonlar 'local_id' ve 'idempotency_key' içermelidir."
                ];
            }

            // 🔒 HER OPERASYON İÇİN AYRI TRANSACTION
            $operationTransaction = $db->beginTransaction(Transaction::SERIALIZABLE);

            try {
                // Transaction timeout ayarla (MySQL için)
                $db->createCommand("SET SESSION innodb_lock_wait_timeout = 10")->execute();

                // 1. IDEMPOTENCY KONTROLÜ (transaction içinde read)
                $existingRequest = $db->createCommand(
                    'SELECT * FROM processed_requests WHERE idempotency_key = :idempotency_key'
                )->bindValue(':idempotency_key', $idempotencyKey)->queryOne();

                if ($existingRequest) {
                    // 2. Bu işlem daha önce yapılmışsa, kayıtlı sonucu döndür.
                    $this->logToFile("Cached result found for idempotency_key: $idempotencyKey", 'DEBUG');
                    $resultData = json_decode($existingRequest['response_body'], true);
                    $results[] = [
                        'local_id' => (int)$localId,
                        'result' => is_string($resultData) ? json_decode($resultData, true) : $resultData
                    ];

                    // Transaction'ı commit et (sadece okuma yaptık ama iyi pratik)
                    $operationTransaction->commit();
                    continue; // Sonraki operasyona geç
                }

                // 3. Yeni işlem ise, operasyonu işle.
                $opType = $op['type'] ?? 'unknown';
                $opData = $op['data'] ?? [];
                $result = ['status' => 'error', 'message' => "Bilinmeyen operasyon tipi: {$opType}"];

                if ($opType === 'goodsReceipt') {
                    $this->logToFile("Creating goods receipt for local_id: $localId", 'DEBUG');
                    $result = $this->_createGoodsReceipt($opData, $db);
                    $this->logToFile("Goods receipt result: " . json_encode($result), 'DEBUG');
                } elseif ($opType === 'inventoryTransfer') {
                    $result = $this->_createInventoryTransfer($opData, $db);
                } elseif ($opType === 'forceCloseOrder') {
                    $result = $this->_forceCloseOrder($opData, $db);
                } elseif ($opType === 'warehouseCount') {
                    $this->logToFile("Creating warehouse count for local_id: $localId", 'DEBUG');
                    $this->logToFile("Warehouse count opData structure: " . json_encode($opData), 'DEBUG');
                    $this->logToFile("Warehouse count opData keys: " . json_encode(array_keys($opData)), 'DEBUG');
                    if (isset($opData['header'])) {
                        $this->logToFile("Warehouse count header keys: " . json_encode(array_keys($opData['header'])), 'DEBUG');
                    }
                    if (isset($opData['items'])) {
                        $this->logToFile("Warehouse count items count: " . count($opData['items']), 'DEBUG');
                    }
                    $result = $this->_createWarehouseCount($opData, $db);
                    $this->logToFile("Warehouse count result: " . json_encode($result), 'DEBUG');
                } elseif ($opType === 'inventoryStock') {
                    // Inventory stock sync removed - use normal table sync instead
                    $result = ['status' => 'error', 'message' => 'Inventory stock sync operations are no longer supported via pending operations'];
                }

                // 4. Sonucu kontrol et
                if (isset($result['status'])) {
                    // Permanent error durumu - bu hatalar tekrar denenmemeli
                    if ($result['status'] === 'permanent_error') {
                        // Permanent error'u idempotency tablosuna kaydet
                        $db->createCommand()->insert('processed_requests', [
                            'idempotency_key' => $idempotencyKey,
                            'response_code' => 400, // Permanent error için 400
                            'response_body' => json_encode($result)
                        ])->execute();

                        // Result dizisine ekle - mobil taraf bunu handle edecek
                        $results[] = [
                            'local_id' => (int)$localId,
                            'idempotency_key' => $idempotencyKey,
                            'result' => $result
                        ];

                        $this->logToFile("Permanent error for operation $localId: " . $result['message'], 'WARNING');

                        // ✅ COMMIT: Permanent error kaydedildi, bir sonraki operasyona geç
                        $operationTransaction->commit();
                        continue;
                    }
                    // Başarılı işlem
                    elseif ($result['status'] === 'success') {
                        $db->createCommand()->insert('processed_requests', [
                            'idempotency_key' => $idempotencyKey,
                            'response_code' => 200,
                            'response_body' => json_encode($result)
                        ])->execute();

                        $results[] = ['local_id' => (int)$localId, 'idempotency_key' => $idempotencyKey, 'result' => $result];

                        // ✅ COMMIT: Başarılı operasyon tamamlandı
                        $operationTransaction->commit();
                    }
                    // Geçici hata - retry yapılabilir
                    else {
                        // Geçici hataları idempotency'e kaydetmiyoruz ki tekrar denenebilsin
                        $errorMsg = "İşlem (ID: {$localId}, Tip: {$opType}) başarısız: " . ($result['message'] ?? 'Bilinmeyen hata');
                        $this->logToFile($errorMsg, 'ERROR');

                        // ❌ ROLLBACK: Geçici hata, tekrar denenebilir
                        $operationTransaction->rollBack();

                        // ⚠️ Bu operasyonu results'a ekleme - mobil tekrar gönderecek
                        // Diğer operasyonlara devam et
                        continue;
                    }
                } else {
                    // Status yoksa genel hata
                    $errorMsg = "İşlem (ID: {$localId}, Tip: {$opType}) başarısız: " . ($result['message'] ?? 'Bilinmeyen hata');
                    $this->logToFile($errorMsg, 'ERROR');

                    // ❌ ROLLBACK: Geçersiz result format
                    $operationTransaction->rollBack();
                    continue;
                }

            } catch (\Exception $e) {
                // ❌ ROLLBACK: Exception oluştu
                $operationTransaction->rollBack();

                $errorDetail = "Operation $localId ($opType) failed: {$e->getMessage()}";
                $this->logToFile($errorDetail, 'ERROR');
                $this->logToFile("Stack trace: " . $e->getTraceAsString(), 'ERROR');

                // ⚠️ Bu operasyonu results'a ekleme - mobil tekrar gönderecek
                // Diğer operasyonlara devam et
                continue;
            }
        }

        // 📊 Tüm operasyonlar işlendi (başarılı veya başarısız)
        return ['success' => true, 'results' => $results];
    }

    /**
     * _key değerini UrunId'ye dönüştürür
     * Eğer _key geliyorsa, urunler tablosundan UrunId'yi bulur
     * Eğer sayısal bir değer geliyorsa direkt döndürür
     */
    private function getProductIdFromKey($productIdOrKey, $db) {
        // Önce _key olarak ara (sayısal görünse bile _key olabilir)
        $urunId = (new Query())
            ->select('UrunId')
            ->from('urunler')
            ->where(['_key' => $productIdOrKey])
            ->scalar($db);
            
        if ($urunId) {
            return (int)$urunId;
        }
        
        // _key bulunamazsa ve sayısalsa, direkt UrunId olabilir
        if (is_numeric($productIdOrKey)) {
            // UrunId'nin gerçekten var olduğunu kontrol et
            $exists = (new Query())
                ->select('UrunId')
                ->from('urunler')
                ->where(['UrunId' => (int)$productIdOrKey])
                ->scalar($db);
            if ($exists) {
                return (int)$productIdOrKey;
            }
        }
        
        // Son olarak StokKodu olarak kontrol et
        $urunId = (new Query())
            ->select('UrunId')
            ->from('urunler')
            ->where(['StokKodu' => $productIdOrKey])
            ->scalar($db);
        
        return $urunId ? (int)$urunId : null;
    }

    private function _createGoodsReceipt($data, $db) {
        $validationError = $this->validateGoodsReceiptData($data);
        if ($validationError) {
            return ['status' => 'error', 'message' => $validationError];
        }

        $header = $data['header'];
        $items = $data['items'];
        $operationUniqueId = $data['operation_unique_id'] ?? null;

        // UUID bazlı duplicate kontrolü
        if ($operationUniqueId) {
            $existingReceipt = $db->createCommand(
                'SELECT * FROM goods_receipts WHERE operation_unique_id = :operation_unique_id'
            )->bindValue(':operation_unique_id', $operationUniqueId)->queryOne();

            if ($existingReceipt) {
                $this->logToFile("Duplicate receipt detected with operation_unique_id: $operationUniqueId", 'WARNING');
                return [
                    'status' => 'success',
                    'message' => 'Receipt already exists',
                    'receipt_id' => $existingReceipt['goods_receipt_id'],
                    'duplicate' => true
                ];
            }
        }

        $siparisId = $header['siparis_id'] ?? null;
        $deliveryNoteNumber = $header['delivery_note_number'] ?? null;

        // Serbest mal kabulde fiş numarası zorunludur.
        if ($siparisId === null && empty($deliveryNoteNumber)) {
            return ['status' => 'error', 'message' => 'Serbest mal kabul için irsaliye numarası (delivery_note_number) zorunludur.'];
        }

        // KRITIK: Sipariş durumu kontrolü - kapanmış siparişe mal kabul yapılamaz
        if ($siparisId !== null) {
            $orderStatus = $db->createCommand(
                'SELECT status FROM siparisler WHERE id = :id'
            )->bindValue(':id', $siparisId)->queryScalar();

            if ($orderStatus === false) {
                return [
                    'status' => 'permanent_error',
                    'error_code' => 'ORDER_NOT_FOUND',
                    'message' => "Sipariş bulunamadı: #$siparisId"
                ];
            }

            // Status: 0=Açık, 1=Kısmi Teslim, 2=Manuel Kapatıldı
            if ($orderStatus == 2) {
                // Çalışan bilgisini al
                $employeeName = 'Unknown';
                if (isset($header['employee_id'])) {
                    $employee = $db->createCommand(
                        'SELECT first_name, last_name FROM employees WHERE id = :id'
                    )->bindValue(':id', $header['employee_id'])->queryOne();
                    if ($employee) {
                        $employeeName = trim($employee['first_name'] . ' ' . $employee['last_name']);
                    }
                }

                // Sipariş numarasını al (fisno)
                $orderNumber = $db->createCommand(
                    'SELECT fisno FROM siparisler WHERE id = :id'
                )->bindValue(':id', $siparisId)->queryScalar();

                $errorMessage = "Sipariş #$orderNumber manuel olarak kapatılmış durumda. Bu siparişe mal kabul yapılamaz.";

                // Yöneticilere bildirim gönder
                try {
                    WMSTelegramNotification::notifyGoodsReceiptError(
                        $employeeName,
                        $orderNumber ?: $siparisId,
                        'Kapalı siparişe mal kabul denemesi',
                        [
                            'Depo' => $header['warehouse_code'] ?? 'Unknown',
                            'İrsaliye No' => $deliveryNoteNumber ?? 'N/A'
                        ]
                    );
                } catch (\Exception $e) {
                    Yii::warning("Telegram notification gönderilemedi: " . $e->getMessage(), __METHOD__);
                }

                return [
                    'status' => 'permanent_error',
                    'error_code' => 'ORDER_CLOSED',
                    'message' => $errorMessage
                ];
            }
        }

        // Çalışanın depo ID'sini al - Rowhub formatında
        $employeeId = $header['employee_id'];
        
        // DEBUG: Employee warehouse mapping'i kontrol et
        $employeeInfo = $db->createCommand(
            'SELECT e.id, e.warehouse_code, w.id, w.warehouse_code as w_warehouse_code
             FROM employees e
             LEFT JOIN warehouses w ON e.warehouse_code = w.warehouse_code
             WHERE e.id = :employee_id'
        )->bindValue(':employee_id', $employeeId)->queryOne();
            
        Yii::info("DEBUG createGoodsReceipt - employee_id: $employeeId", __METHOD__);
        Yii::info("DEBUG employee info: " . json_encode($employeeInfo), __METHOD__);
        
        $warehouseId = $employeeInfo['id'] ?? null;

        if (!$warehouseId) {
            return ['status' => 'error', 'message' => 'Çalışanın warehouse bilgisi bulunamadı. Employee warehouse_code: ' . ($employeeInfo['warehouse_code'] ?? 'null')];
        }

        // Sipariş fisno bilgisini al
        $sipFisno = null;
        if ($siparisId) {
            $sipFisno = $db->createCommand(
                'SELECT fisno FROM siparisler WHERE id = :id'
            )->bindValue(':id', $siparisId)->queryScalar();
        }

        $db->createCommand()->insert('goods_receipts', [
            'operation_unique_id' => $data['operation_unique_id'] ?? null, // Tag and Replace reconciliation için
            'receipt_date' => $header['receipt_date'] ?? new \yii\db\Expression('NOW()'),
            'employee_id' => $header['employee_id'],
            'siparis_id' => $siparisId,
            'delivery_note_number' => $deliveryNoteNumber,
            'warehouse_code' => $employeeInfo['warehouse_code'] ?? null,
            'warehouse_id' => $warehouseId, // DÜZELTME: warehouse_id eklendi (required field)
            'sip_fisno' => $sipFisno,
        ])->execute();
        $receiptId = $db->getLastInsertID();

        foreach ($items as $item) {
            // Mobile'dan urun_key (_key değeri) geliyor, direkt yazılıyor
            $urunKey = $item['urun_key']; // _key değeri
            
            // _key'in gerçekten var olduğunu kontrol et
            $exists = $db->createCommand(
                'SELECT 1 FROM urunler WHERE _key = :key LIMIT 1'
            )->bindValue(':key', $urunKey)->queryScalar();

            if (!$exists) {
                return ['status' => 'error', 'message' => 'Ürün bulunamadı: ' . $urunKey];
            }
            
            // Sipariş bazlı mal kabulde siparis_key'i bul ve free kontrolü yap
            $siparisKey = null;
            $stokKodu = null;
            $isFree = 1; // Varsayılan olarak free (sipariş dışı)
            
            // Ürünün StokKodu'nu al
            $stokKodu = $this->getStokKoduByUrunKey($urunKey, $db);
            
            if ($siparisId && $stokKodu) {
                // Gelen ürünün birim bilgisini al (item'dan geliyor olmalı)
                $birimKey = $item['birim_key'] ?? null;
                
                // Siparişte bu ürün ve birim kombinasyonu var mı kontrol et
                if ($birimKey) {
                    $isInOrder = $db->createCommand(
                        'SELECT 1 FROM siparis_ayrintili
                         WHERE siparisler_id = :siparis_id AND kartkodu = :kartkodu
                           AND sipbirimkey = :birimkey AND turu = \'1\'
                         LIMIT 1'
                    )->bindValue(':siparis_id', $siparisId)
                     ->bindValue(':kartkodu', $stokKodu)
                     ->bindValue(':birimkey', $birimKey)
                     ->queryScalar();
                    
                    // Eğer siparişteki ürün ve birimle eşleşiyorsa free=0
                    if ($isInOrder) {
                        $isFree = 0;
                        
                        // siparis_ayrintili tablosundan _key değerini bul
                        $siparisKey = $db->createCommand(
                            'SELECT _key FROM siparis_ayrintili
                             WHERE siparisler_id = :siparis_id AND kartkodu = :kartkodu
                               AND sipbirimkey = :birimkey AND turu = \'1\''
                        )->bindValue(':siparis_id', $siparisId)
                         ->bindValue(':kartkodu', $stokKodu)
                         ->bindValue(':birimkey', $birimKey)
                         ->queryScalar();
                    }
                } else {
                    // Birim bilgisi yoksa sadece ürün kontrolü yap (geriye uyumluluk için)
                    $siparisKey = $db->createCommand(
                        'SELECT _key FROM siparis_ayrintili
                         WHERE siparisler_id = :siparis_id AND kartkodu = :kartkodu AND turu = \'1\''
                    )->bindValue(':siparis_id', $siparisId)
                     ->bindValue(':kartkodu', $stokKodu)
                     ->queryScalar();
                    
                    if ($siparisKey) {
                        $isFree = 0; // Siparişteki ürün bulundu
                    }
                }
            }
            
            // KRITIK DEBUG: birim_key değerini kontrol et
            $this->logToFile("Inserting goods_receipt_item - urun_key: $urunKey, birim_key: " . ($item['birim_key'] ?? 'NULL'), 'DEBUG');
            $this->logToFile("Raw item data: " . json_encode($item), 'DEBUG');
            
            $db->createCommand()->insert('goods_receipt_items', [
                'receipt_id' => $receiptId, 
                'operation_unique_id' => $data['operation_unique_id'] ?? null, // Parent receipt'in operation_unique_id'si
                'item_uuid' => $item['item_uuid'] ?? null, // Item'ın kendi UUID'si
                'urun_key' => $urunKey, // _key değeri direkt yazılıyor
                'birim_key' => $item['birim_key'] ?? null, // Birim _key değeri
                'quantity_received' => $item['quantity'], 
                'pallet_barcode' => $item['pallet_barcode'] ?? null,
                'barcode' => $item['barcode'] ?? null,
                'expiry_date' => $item['expiry_date'] ?? null,
                'siparis_key' => $siparisKey,
                'StokKodu' => $stokKodu,
                'free' => $isFree, // Siparişteki ürün+birim ise 0, değilse 1
            ])->execute();

            // Backend'de inventory_stock oluştur veya güncelle - upsertStock kullanarak birleştir
            $stockStatus = 'receiving'; // Mal kabul aşamasında receiving status
            
            // DEBUG: Birim key kontrolü için log ekle
            Yii::info("DEBUG upsertStock call - urunKey: $urunKey, birimKey: " . ($item['birim_key'] ?? 'NULL') . ", quantity: " . $item['quantity'], __METHOD__);
            
            // KRITIK FIX: Telefondan gelen stock_uuid'yi kullan
            $stockUuid = isset($item['stock_uuid']) ? $item['stock_uuid'] : null;
            Yii::info("DEBUG stock_uuid from phone: " . ($stockUuid ?? 'NULL'), __METHOD__);
            
            $this->upsertStock(
                $db,
                $urunKey,
                $item['birim_key'] ?? null, // Birim _key değeri
                null, // location_id - Mal kabul aşamasında lokasyon yok
                $item['quantity'], // quantity
                $item['pallet_barcode'] ?? null, // pallet_barcode
                $stockStatus, // stock_status
                $siparisId, // siparis_id
                $item['expiry_date'] ?? null, // expiry_date
                $receiptId, // DÜZELTME: goods_receipt_id mal kabulde kaydedilmeli
                $employeeInfo['warehouse_code'] ?? null, // warehouse_code eklendi
                $stockUuid // KRITIK: Telefondan gelen UUID'yi geçir
            );
        }


        // DIA entegrasyonu - Mal kabul işlemi DIA'ya gönderilir
         try {
            $goodsReceipt = GoodsReceipts::find()
                ->where(['goods_receipt_id' => $receiptId])
                ->with(['warehouse', 'warehouse.branch'])
                ->one();
            $goodsReceiptItems = GoodsReceiptItems::find()->where(['receipt_id' => $receiptId])->all();
            
            Yii::info("DIA entegrasyonu başlatılıyor - Receipt ID: $receiptId, Item sayısı: " . count($goodsReceiptItems), __METHOD__);
            
            if ($goodsReceipt && !empty($goodsReceiptItems)) {
                $result = Dia::goodReceiptIrsaliyeEkle($goodsReceipt, $goodsReceiptItems);
                // DIA işlem sonucunu log'a kaydet
                Yii::info("DIA goodReceiptIrsaliyeEkle result for receipt $receiptId: " . json_encode($result), __METHOD__);
                
                // Sonucu response'a ekle
                if($result && isset($result['code'])) {
                    if($result['code'] == '200') {
                        Yii::info("✓ DIA İrsaliye başarıyla oluşturuldu. DIA Key: " . ($result['key'] ?? 'N/A'), __METHOD__);
                    } else {
                        Yii::warning("✗ DIA İrsaliye oluşturulamadı: " . ($result['msg'] ?? 'Bilinmeyen hata'), __METHOD__);
                    }
                }
            } else {
                Yii::warning("DIA entegrasyonu atlandı - Mal kabul veya kalemler bulunamadı", __METHOD__);
            }
        } catch (\Exception $e) {
            // DIA entegrasyonu başarısız olsa bile mal kabul işlemi devam eder
            $this->logToFile("DIA entegrasyonu hatası (Receipt ID: $receiptId): " . $e->getMessage(), 'ERROR');

            // DIA entegrasyon hatası bildirimi
            try {
                WMSTelegramNotification::notifyDIAError(
                    'Mal Kabul İrsaliye Ekleme',
                    $e->getMessage(),
                    [
                        'Mal Kabul ID' => $receiptId,
                        'Sipariş ID' => $siparisId ?? 'Serbest Mal Kabul',
                        'İrsaliye No' => $deliveryNoteNumber ?? 'N/A'
                    ]
                );
            } catch (\Exception $notifE) {
                Yii::warning("DIA error Telegram notification gönderilemedi: " . $notifE->getMessage(), __METHOD__);
            }
        }

        if ($siparisId) {
            $this->checkAndFinalizeReceiptStatus($db, $siparisId);
        }

        return ['status' => 'success', 'receipt_id' => $receiptId, 'operation_unique_id' => $data['operation_unique_id'] ?? null];
    }

    private function _createInventoryTransfer($data, $db) {
        $validationError = $this->validateInventoryTransferData($data);
        if ($validationError) {
            return ['status' => 'error', 'message' => $validationError];
        }
        
        $header = $data['header'];
        $items = $data['items'];

        // Employee warehouse_code bilgisini al
        $employeeInfo = $db->createCommand(
            'SELECT warehouse_code FROM employees WHERE id = :id'
        )->bindValue(':id', $header['employee_id'])->queryOne();

        $sourceLocationId = ($header['source_location_id'] == 0) ? null : $header['source_location_id'];
        $targetLocationId = $header['target_location_id'];
        $operationType = $header['operation_type'] ?? 'product_transfer';
        $siparisId = $header['siparis_id'] ?? null;
        $goodsReceiptId = $header['goods_receipt_id'] ?? null;
        $deliveryNoteNumber = $header['delivery_note_number'] ?? null;

        // Rafa yerleştirme işlemi sanal mal kabul alanından (kaynak_lokasyon_id NULL) yapılan herhangi bir transferdir
        $isPutawayOperation = ($sourceLocationId === null);
        $sourceStatus = $isPutawayOperation ? 'receiving' : 'available';

        foreach ($items as $item) {
            // Mobile'dan _key değeri geliyor, direkt kullanılıyor
            $urunKey = $item['urun_key']; // _key değeri
            $birimKey = $item['birim_key'] ?? null; // Birim _key değeri
            
            // _key'in gerçekten var olduğunu kontrol et ve detaylı hata mesajı ver
            $productInfo = $db->createCommand(
                'SELECT _key, StokKodu, UrunAdi FROM urunler WHERE _key = :key'
            )->bindValue(':key', $urunKey)->queryOne();
            
            if (!$productInfo) {
                // Alternative: Try to find by UrunId if _key is actually a numeric value
                if (is_numeric($urunKey)) {
                    $productInfo = $db->createCommand(
                        'SELECT _key, StokKodu, UrunAdi FROM urunler WHERE UrunId = :id'
                    )->bindValue(':id', (int)$urunKey)->queryOne();
                    
                    if ($productInfo) {
                        // Use the correct _key from database
                        $urunKey = $productInfo['_key'];
                        Yii::warning("Transfer: Converted UrunId {$item['urun_key']} to _key {$urunKey}", __METHOD__);
                    }
                }
                
                if (!$productInfo) {
                    $errorMessage = "Ürün bulunamadı: {$item['urun_key']} (tip: " . gettype($item['urun_key']) . ")";

                    // Çalışan bilgisini al
                    $employeeName = 'Bilinmeyen';
                    if (isset($header['employee_id'])) {
                        $employeeData = $db->createCommand(
                            'SELECT name FROM employees WHERE id = :id'
                        )->bindValue(':id', $header['employee_id'])->queryOne();
                        if ($employeeData) {
                            $employeeName = $employeeData['name'];
                        }
                    }

                    // Telegram bildirimi gönder
                    try {
                        WMSTelegramNotification::notifyTransferError(
                            $employeeName,
                            $errorMessage,
                            [
                                'Arınan Ürün Key' => $item['urun_key'],
                                'Tip' => gettype($item['urun_key']),
                                'Kaynak Lokasyon' => $sourceLocationId ?? 'Mal Kabul Alanı',
                                'Hedef Lokasyon' => $targetLocationId ?? 'Unknown'
                            ]
                        );
                    } catch (\Exception $e) {
                        Yii::warning("Telegram notification gönderilemedi: " . $e->getMessage(), __METHOD__);
                    }

                    return ['status' => 'error', 'message' => $errorMessage];
                }
            }
            
            $totalQuantityToTransfer = (float)$item['quantity'];
            $sourcePallet = $item['pallet_id'] ?? null;
            $stockUuid = $item['stock_uuid'] ?? null; // KRITIK FIX: Phone-generated UUID
            $targetPallet = ($operationType === 'pallet_transfer') ? $sourcePallet : null;

            // 1. İlk giren ilk çıkar mantığı ile kaynak stokları bul
            $sourceStocksQuery = new Query();
            $sourceStocksQuery->from('inventory_stock')
                ->where(['urun_key' => $urunKey, 'stock_status' => $sourceStatus]);
            $this->addNullSafeWhere($sourceStocksQuery, 'birim_key', $birimKey);
            $this->addNullSafeWhere($sourceStocksQuery, 'location_id', $sourceLocationId);
            $this->addNullSafeWhere($sourceStocksQuery, 'pallet_barcode', $sourcePallet);

            // Rafa yerleştirme işlemleri için, belirli sipariş veya fişe göre filtrelememiz gerekir
            if ($isPutawayOperation) {
                if ($siparisId) {
                    $this->addNullSafeWhere($sourceStocksQuery, 'siparis_id', $siparisId);
                } elseif ($deliveryNoteNumber) {
                    // Serbest mal kabul için irsaliye numarası üzerinden fiş ID'sini bul
                    $actualGoodsReceiptId = $db->createCommand(
                        'SELECT goods_receipt_id FROM goods_receipts WHERE delivery_note_number = :delivery_note'
                    )->bindValue(':delivery_note', $deliveryNoteNumber)->queryScalar();
                    if ($actualGoodsReceiptId) {
                        $this->addNullSafeWhere($sourceStocksQuery, 'goods_receipt_id', $actualGoodsReceiptId);
                        // hata bağlamı ve sonraki işlemler için mal kabul ID'sini güncelle
                        $goodsReceiptId = $actualGoodsReceiptId;
                    }
                } elseif ($goodsReceiptId) {
                    $this->addNullSafeWhere($sourceStocksQuery, 'goods_receipt_id', $goodsReceiptId);
                }
            }

            $sourceStocksQuery->orderBy(['expiry_date' => SORT_ASC]);
            $sourceStocks = $sourceStocksQuery->all($db);

            $totalAvailable = array_sum(array_column($sourceStocks, 'quantity'));
            if ($totalAvailable < $totalQuantityToTransfer - 0.001) {
                $errorContext = $isPutawayOperation ? "Putaway for Receipt #$goodsReceiptId / Order #$siparisId" : "Shelf Transfer";
                $errorMessage = "Yetersiz stok. Ürün ID: {$urunKey}, Mevcut: {$totalAvailable}, İstenen: {$totalQuantityToTransfer}";

                // Çalışan bilgisini al
                $employeeName = 'Bilinmeyen';
                if (isset($header['employee_id'])) {
                    $employeeData = $db->createCommand(
                        'SELECT name FROM employees WHERE id = :id'
                    )->bindValue(':id', $header['employee_id'])->queryOne();
                    if ($employeeData) {
                        $employeeName = $employeeData['name'];
                    }
                }

                // Telegram bildirimi gönder
                try {
                    WMSTelegramNotification::notifyTransferError(
                        $employeeName,
                        $errorMessage,
                        [
                            'İşlem Tipi' => $errorContext,
                            'Ürün Kodu' => $productInfo['StokKodu'] ?? 'Unknown',
                            'Ürün Adı' => $productInfo['UrunAdi'] ?? 'Unknown',
                            'Kaynak Lokasyon' => $sourceLocationId ?? 'Mal Kabul Alanı',
                            'Hedef Lokasyon' => $targetLocationId ?? 'Unknown'
                        ]
                    );
                } catch (\Exception $e) {
                    Yii::warning("Telegram notification gönderilemedi: " . $e->getMessage(), __METHOD__);
                }

                return ['status' => 'error', 'message' => $errorMessage . ". Context: {$errorContext}"];
            }

            // 2. Transfer edilecek kısımları ve gerekli veritabanı işlemlerini belirle
            $quantityLeft = $totalQuantityToTransfer;
            $portionsToTransfer = []; // {miktar, son_kullanma_tarihi, siparis_id, mal_kabul_id}
            $vtIslemleri = ['delete' => [], 'update' => []]; // {id: yeni_miktar}

            foreach ($sourceStocks as $stock) {
                if ($quantityLeft <= 0.001) break;

                $stockId = $stock['id'];
                $stockQty = (float)$stock['quantity'];
                $qtyThisCycle = min($stockQty, $quantityLeft);

                $portionsToTransfer[] = [
                    'qty' => $qtyThisCycle,
                    'expiry' => $stock['expiry_date'],
                    'siparis_id' => $stock['siparis_id'],
                    'goods_receipt_id' => $stock['goods_receipt_id']
                ];

                if ($stockQty - $qtyThisCycle > 0.001) {
                    $vtIslemleri['update'][$stockId] = $stockQty - $qtyThisCycle;
                } else {
                    $vtIslemleri['delete'][] = $stockId;
                }
                $quantityLeft -= $qtyThisCycle;
            }

            // 3. Veritabanı işlemlerini çalıştır (Kaynağı azalt)
            if (!empty($vtIslemleri['delete'])) {
                // TOMBSTONE: Silinecek stokların UUID'lerini log tablosuna kaydet (YENİ UUID TABANLI YAKLAŞIM)
                $stockUuids = $db->createCommand(
                    'SELECT stock_uuid FROM inventory_stock WHERE id IN (' . implode(',', array_map('intval', $vtIslemleri['delete'])) . ')'
                )->queryColumn();

                // UUID'leri tombstone tablosuna toplu olarak ekle
                if (!empty($stockUuids)) {
                    $recordsToLog = [];
                    foreach ($stockUuids as $uuid) {
                        $recordsToLog[] = [
                            'stock_uuid' => $uuid,
                            'warehouse_code' => $employeeInfo['warehouse_code'] ?? null,
                            'deleted_at' => new \yii\db\Expression('NOW()')
                        ];
                    }
                    
                    // Convert to wms_tombstones format
                    $tombstoneRecords = [];
                    foreach ($stockUuids as $uuid) {
                        $tombstoneRecords[] = [
                            $uuid,
                            $employeeInfo['warehouse_code'] ?? null,
                            new \yii\db\Expression('NOW()')
                        ];
                    }
                    
                    $db->createCommand()->batchInsert(
                        'wms_tombstones',
                        ['stock_uuid', 'warehouse_code', 'deleted_at'],
                        $tombstoneRecords
                    )->execute();
                    
                    Yii::info("TOMBSTONE: Logged " . count($stockUuids) . " deleted inventory_stock UUIDs", __METHOD__);
                }
                
                // Ana tablodan fiziksel olarak sil
                $db->createCommand()->delete('inventory_stock', ['in', 'id', $vtIslemleri['delete']])->execute();
            }
            foreach ($vtIslemleri['update'] as $id => $newQty) {
                $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $id])->execute();
            }

            // 4. Kısımları hedefe ekle (son kullanma tarihleri ve kaynak ID'leri korunarak)
            foreach($portionsToTransfer as $portion) {
                $this->upsertStock(
                    $db,
                    $urunKey, // _key kullanılıyor
                    $birimKey, // Birim _key değeri
                    $targetLocationId,
                    $portion['qty'],
                    $targetPallet,
                    'available',
                    // KRITIK FIX: 'available' durumunda siparis_id = null - konsolidasyon için
                    null,
                    $portion['expiry'],
                    null, // KRITIK FIX: goods_receipt_id NULL - consolidation için
                    $employeeInfo['warehouse_code'] ?? null, // warehouse_code eklendi
                    $stockUuid // KRITIK FIX: Phone-generated UUID
                );

                // 5. Her kısım için ayrı transfer kaydı oluştur
                // _key urun_key olarak kullanılıyor
                
                // StokKodu'nu urun_key'den al
                $stokKodu = $this->getStokKoduByUrunKey($urunKey, $db);
                    
                // Shelf code'ları al
                $fromShelfCode = $sourceLocationId ? $db->createCommand(
                    'SELECT code FROM shelfs WHERE id = :id'
                )->bindValue(':id', $sourceLocationId)->queryScalar() : null;

                $toShelfCode = $targetLocationId ? $db->createCommand(
                    'SELECT code FROM shelfs WHERE id = :id'
                )->bindValue(':id', $targetLocationId)->queryScalar() : null;

                // Sipariş fisno'sunu al
                $sipFisno = $siparisId ? $db->createCommand(
                    'SELECT fisno FROM siparisler WHERE id = :id'
                )->bindValue(':id', $siparisId)->queryScalar() : null;
                
                $transferData = [
                    'operation_unique_id' => $data['operation_unique_id'] ?? null, // Tag and Replace reconciliation için
                    'urun_key'            => $urunKey, // _key yazılıyor
                    'birim_key'           => $birimKey, // DÜZELTME: $birimKey değişkenini kullan
                    'from_location_id'    => $sourceLocationId,
                    'to_location_id'      => $targetLocationId,
                    'quantity'            => $portion['qty'],
                    'from_pallet_barcode' => $sourcePallet,
                    'pallet_barcode'      => $targetPallet,
                    'goods_receipt_id'    => $goodsReceiptId,
                    'delivery_note_number' => $deliveryNoteNumber,
                    'employee_id'         => $header['employee_id'],
                    'transfer_date'       => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
                    'StokKodu'            => $stokKodu,
                    'from_shelf'          => $fromShelfCode,
                    'to_shelf'            => $toShelfCode,
                    'sip_fisno'           => $sipFisno,
                ];

                if ($siparisId) {
                    $transferData['siparis_id'] = $siparisId;
                }

                $db->createCommand()->insert('inventory_transfers', $transferData)->execute();
            }

            // 6. wms_putaway_status tablosu kaldırıldı - putaway durumu inventory_stock'tan takip ediliyor
        }

        // checkAndFinalizePoStatus fonksiyonu kaldırıldı - wms_putaway_status tablosu artık yok

        // Son eklenen transfer kaydının ID'sini al
        $lastTransferId = $db->getLastInsertID();
        
        // RETURN İFADESİNİ GÜNCELLE
        return ['status' => 'success', 'transfer_id' => $lastTransferId, 'operation_unique_id' => $data['operation_unique_id'] ?? null];
    }

    private function upsertStock($db, $urunKey, $birimKey, $locationId, $qtyChange, $palletBarcode, $stockStatus, $siparisId = null, $expiryDate = null, $goodsReceiptId = null, $warehouseCode = null, $stockUuid = null) {
        $isDecrement = (float)$qtyChange < 0;

        if ($isDecrement) {
            // Bu fonksiyon artık _createInventoryTransfer'da kullanılmıyor,
            // ama diğer yerlerde kullanılma ihtimaline karşı bırakıldı.
            // Mantığı önceki adımdaki gibi (while döngüsü) kalabilir.
            $toDecrement = abs((float)$qtyChange);

            $availabilityQuery = new Query();
            $availabilityQuery->from('inventory_stock')->where(['urun_key' => $urunKey, 'stock_status' => $stockStatus]);
            $this->addNullSafeWhere($availabilityQuery, 'birim_key', $birimKey);
            $this->addNullSafeWhere($availabilityQuery, 'location_id', $locationId);
            $this->addNullSafeWhere($availabilityQuery, 'pallet_barcode', $palletBarcode);
            // KRITIK FIX: Receiving durumunda siparis_id ile match et
            if ($stockStatus === 'receiving' && $siparisId !== null) {
                $this->addNullSafeWhere($availabilityQuery, 'siparis_id', $siparisId);
            }
            $totalAvailable = (float)$availabilityQuery->sum('quantity', $db);

            if ($totalAvailable < $toDecrement - 0.001) {
                 throw new \Exception("Stok düşürme hatası: Kaynakta yeterli stok yok. Mevcut: {$totalAvailable}, İstenen: {$toDecrement}");
            }

            while ($toDecrement > 0.001) {
                $query = new Query();
                $query->from('inventory_stock')->where(['urun_key' => $urunKey, 'stock_status' => $stockStatus]);
                $this->addNullSafeWhere($query, 'birim_key', $birimKey);
                $this->addNullSafeWhere($query, 'location_id', $locationId);
                $this->addNullSafeWhere($query, 'pallet_barcode', $palletBarcode);
                // KRITIK FIX: Receiving durumunda siparis_id ile match et
                if ($stockStatus === 'receiving' && $siparisId !== null) {
                    $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
                }
                $query->orderBy(['expiry_date' => SORT_ASC])->limit(1);

                $stock = $query->createCommand($db)->queryOne();

                if (!$stock) {
                    throw new \Exception("Stok düşürme sırasında tutarsızlık tespit edildi. Kalan: {$toDecrement}");
                }

                $stockId = $stock['id'];
                $currentQty = (float)$stock['quantity'];

                if ($currentQty > $toDecrement) {
                    $newQty = $currentQty - $toDecrement;
                    $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $stockId])->execute();
                    $toDecrement = 0;
                } else {
                    // TOMBSTONE: UUID'yi log tablosuna kaydet
                    $this->logSingleDeletion($db, $stockId);
                    
                    $db->createCommand()->delete('inventory_stock', ['id' => $stockId])->execute();
                    $toDecrement -= $currentQty;
                }
            }
        } else {
            // --- Stok Ekleme Mantığı ---
            // KRITIK FIX: 'receiving' durumunda siparis_id'yi de konsolidasyon kontrolüne dahil et
            // 'available' durumunda ise siparis_id'yi ignore et (konsolidasyon için)
            $query = new Query();
            $query->from('inventory_stock')
                  ->where(['urun_key' => $urunKey, 'stock_status' => $stockStatus]);

            $this->addNullSafeWhere($query, 'birim_key', $birimKey);
            $this->addNullSafeWhere($query, 'location_id', $locationId);
            $this->addNullSafeWhere($query, 'pallet_barcode', $palletBarcode);
            $this->addNullSafeWhere($query, 'expiry_date', $expiryDate);
            
            // KRITIK FIX: 'receiving' durumunda siparis_id'yi dahil et - farklı siparişler ayrı tutulmalı
            // Serbest mal kabul (siparis_id=NULL) ve sipariş bazlı mal kabul ayrı kayıtlarda tutulmalı
            if ($stockStatus === 'receiving') {
                $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
                // KRITIK FIX: Farklı delivery note'lar için ayrı stock tutmalıyız
                $this->addNullSafeWhere($query, 'goods_receipt_id', $goodsReceiptId);
            }
            // 'available' durumunda siparis_id kontrolü YOK - konsolidasyon için

            $stock = $query->createCommand($db)->queryOne();

            if ($stock) {
                // DEBUG: Stok birleştirme kontrolü
                Yii::info("DEBUG stock merge - Found existing stock ID: {$stock['id']}, current: {$stock['quantity']}, adding: $qtyChange", __METHOD__);
                
                $newQty = (float)($stock['quantity']) + (float)$qtyChange;
                if ($newQty > 0.001) {
                    $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $stock['id']])->execute();
                    Yii::info("DEBUG stock merge - Updated quantity to: $newQty", __METHOD__);
                } else {
                    // TOMBSTONE: UUID'yi log tablosuna kaydet
                    $this->logSingleDeletion($db, $stock['id']);
                    
                    $db->createCommand()->delete('inventory_stock', ['id' => $stock['id']])->execute();
                    Yii::info("DEBUG stock merge - Deleted zero quantity stock", __METHOD__);
                }
            } elseif ($qtyChange > 0) {
                // Verify urun_key exists before inserting
                $productExists = $db->createCommand(
                    'SELECT 1 FROM urunler WHERE _key = :key LIMIT 1'
                )->bindValue(':key', $urunKey)->queryScalar();
                    
                if (!$productExists) {
                    $this->logToFile("CRITICAL ERROR: urun_key '{$urunKey}' does not exist in urunler table", 'ERROR');
                    throw new \Exception("Cannot insert inventory_stock: urun_key '{$urunKey}' does not exist in urunler table");
                }
                
                // _key urun_key olarak kullanılıyor
                
                // Yeni sütunlar için veri al
                $stokKodu = $this->getStokKoduByUrunKey($urunKey, $db);

                $shelfCode = $locationId ? $db->createCommand(
                    'SELECT code FROM shelfs WHERE id = :id'
                )->bindValue(':id', $locationId)->queryScalar() : null;

                $sipFisno = $siparisId ? $db->createCommand(
                    'SELECT fisno FROM siparisler WHERE id = :id'
                )->bindValue(':id', $siparisId)->queryScalar() : null;
                
                // DEBUG: Yeni stok kaydı oluşturma
                Yii::info("DEBUG creating new stock - urunKey: $urunKey, birimKey: $birimKey, quantity: $qtyChange", __METHOD__);
                
                // UUID: Telefondan gelen UUID'yi kullan, yoksa yeni üret
                $finalStockUuid = $stockUuid ?? $this->generateUuid();
                Yii::info("DEBUG stock UUID: $finalStockUuid (from phone: " . ($stockUuid ? 'yes' : 'no') . ")", __METHOD__);
                
                // Kapsamlı UUID takip logging'i
                if ($stockUuid) {
                    Yii::info("UUID FLOW: Phone-generated UUID $stockUuid being stored for urun_key=$urunKey, birim_key=$birimKey", __METHOD__);
                } else {
                    Yii::info("UUID FLOW: Server-generated UUID $finalStockUuid created for urun_key=$urunKey, birim_key=$birimKey", __METHOD__);
                }
                
                $db->createCommand()->insert('inventory_stock', [
                    'stock_uuid' => $finalStockUuid, // UUID eklendi
                    'urun_key' => $urunKey, 
                    'birim_key' => $birimKey, // Birim _key değeri
                    'location_id' => $locationId, 
                    'siparis_id' => $siparisId,
                    'quantity' => (float)$qtyChange, 
                    'pallet_barcode' => $palletBarcode,
                    'stock_status' => $stockStatus, 
                    'expiry_date' => $expiryDate,
                    'goods_receipt_id' => $goodsReceiptId, // DÜZELTME: goods_receipt_id eklendi
                    'StokKodu' => $stokKodu,
                    'shelf_code' => $shelfCode,
                    'sip_fisno' => $sipFisno,
                    'warehouse_code' => $warehouseCode, // warehouse_code eklendi
                ])->execute();
            }
        }
    }

    private function addNullSafeWhere(Query $query, string $column, $value) {
        if ($value === null) {
            $query->andWhere(['is', $column, new \yii\db\Expression('NULL')]);
        } else {
            $query->andWhere([$column => $value]);
        }
    }

    private function checkAndFinalizeReceiptStatus($db, $siparisId) {
        if (!$siparisId) return;

        $sql = "
            SELECT
                s.id,
                s.miktar,
                u._key,
                (SELECT COALESCE(SUM(gri.quantity_received), 0)
                 FROM goods_receipt_items gri
                 JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
                 WHERE gr.siparis_id = :siparis_id AND gri.urun_key = u._key
                ) as received_quantity
            FROM siparis_ayrintili s
            JOIN urunler u ON u.StokKodu = s.kartkodu
            WHERE s.siparisler_id = :siparis_id AND s.turu = '1'
        ";
        $lines = $db->createCommand($sql, [':siparis_id' => $siparisId])->queryAll();

        if (empty($lines)) return;

        $anyLineReceived = false;

        foreach ($lines as $line) {
            $received = (float)$line['received_quantity'];

            if ($received > 0.001) {
                $anyLineReceived = true;
                break; // Herhangi bir satırda mal kabul varsa status 1 olacak
            }
        }

        $newStatus = null;
        if ($anyLineReceived) {
            $newStatus = 1; // Kısmi kabul (sipariş edilen > kabul edilen)
        }

        if ($newStatus !== null) {
            $currentStatus = $db->createCommand(
                'SELECT status FROM siparisler WHERE id = :id'
            )->bindValue(':id', $siparisId)->queryScalar();
            if ($currentStatus != $newStatus) {
                $db->createCommand()->update('siparisler', [
                    'status' => $newStatus,
                    'updated_at' => new \yii\db\Expression('NOW()')
                ], ['id' => $siparisId])->execute();
            }
        }
    }


    private function _forceCloseOrder($data, $db) {
        $siparisId = $data['siparis_id'] ?? null;
        if (empty($siparisId)) {
            return ['status' => 'error', 'message' => 'Geçersiz veri: "siparis_id" eksik.'];
        }

        // Önce siparişin mevcut durumunu kontrol et
        $currentStatus = $db->createCommand(
            'SELECT status FROM siparisler WHERE id = :id'
        )->bindValue(':id', $siparisId)->queryScalar();

        if ($currentStatus === false) {
            return ['status' => 'not_found', 'message' => "Order #$siparisId not found."];
        }

        // Sipariş zaten kapalıysa (status 2) permanent error döndür
        if ($currentStatus == 2) {
            // Çalışan bilgisini al
            $employeeName = 'Bilinmeyen';
            if (isset($data['employee_id'])) {
                $employeeData = $db->createCommand(
                    'SELECT name FROM employees WHERE id = :id'
                )->bindValue(':id', $data['employee_id'])->queryOne();
                if ($employeeData) {
                    $employeeName = $employeeData['name'];
                }
            }

            // Telegram bildirimi gönder
            try {
                WMSTelegramNotification::notifyPermanentError(
                    $employeeName,
                    'Sipariş Kapama',
                    "Sipariş #$siparisId zaten kapalı durumda.",
                    ['Sipariş No' => $siparisId]
                );
            } catch (\Exception $e) {
                Yii::warning("Telegram notification gönderilemedi: " . $e->getMessage(), __METHOD__);
            }

            return [
                'status' => 'permanent_error',
                'error_code' => 'ORDER_ALREADY_CLOSED',
                'message' => "Sipariş #$siparisId zaten kapalı durumda."
            ];
        }

        // Statü: 2 (Manuel Kapatıldı)
        $count = $db->createCommand()->update('siparisler', [
            'status' => 2,
            'updated_at' => new \yii\db\Expression('NOW()')
        ], ['id' => $siparisId])->execute();

        if ($count > 0) {
            return ['status' => 'success', 'message' => "Order #$siparisId closed."];
        } else {
            // Kapama başarısız olduysa bildirim gönder
            $employeeName = 'Bilinmeyen';
            if (isset($data['employee_id'])) {
                $employeeData = $db->createCommand(
                    'SELECT name FROM employees WHERE id = :id'
                )->bindValue(':id', $data['employee_id'])->queryOne();
                if ($employeeData) {
                    $employeeName = $employeeData['name'];
                }
            }

            try {
                WMSTelegramNotification::notifyOrderCloseError(
                    $employeeName,
                    $siparisId,
                    "Veritabanı güncellemesi başarısız.",
                    ['Güncellenen Kayıt Sayısı' => $count]
                );
            } catch (\Exception $e) {
                Yii::warning("Telegram notification gönderilemedi: " . $e->getMessage(), __METHOD__);
            }

            return ['status' => 'error', 'message' => "Order #$siparisId could not be closed."];
        }
    }

    /**
     * Telegram bot test endpoint
     * GET /api/terminal/test-telegram
     */
    public function actionTestTelegram()
    {
        try {
            // Önce bot bilgilerini kontrol et
            $botInfo = $this->getBotInfo();

            // Test mesajı gönder
            $result = WMSTelegramNotification::sendTestMessage();

            if ($result) {
                return $this->asJson([
                    'success' => true,
                    'message' => 'Test mesajı başarıyla gönderildi! Telegram grubunuzu kontrol edin.',
                    'bot_info' => $botInfo
                ]);
            } else {
                return $this->asJson([
                    'success' => false,
                    'message' => 'Test mesajı gönderilemedi. Log dosyalarını kontrol edin.',
                    'bot_info' => $botInfo,
                    'debug' => 'Detaylı hata bilgileri Yii log\'larında bulunabilir.'
                ]);
            }
        } catch (\Exception $e) {
            return $this->asJson([
                'success' => false,
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
        }
    }

    private function getBotInfo()
    {
        $botToken = WMSTelegramNotification::TELEGRAM_BOT_TOKEN;
        $url = "https://api.telegram.org/bot{$botToken}/getMe";

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);

        $result = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($httpCode === 200) {
            return json_decode($result, true);
        }

        return ['error' => "HTTP $httpCode", 'response' => $result];
    }

    /**
     * Telegram debug endpoint - Ham API response görür
     * GET /api/terminal/test-telegram-debug
     */
    public function actionTestTelegramDebug()
    {
        try {
            $botToken = WMSTelegramNotification::TELEGRAM_BOT_TOKEN;
            $chatId = WMSTelegramNotification::TELEGRAM_CHAT_ID;
            $url = "https://api.telegram.org/bot{$botToken}/sendMessage";

            $message = "🔧 DEBUG TEST\n\nBu bir debug test mesajıdır.";

            // Manuel API çağrısı yap
            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_POST, true);
            curl_setopt($ch, CURLOPT_POSTFIELDS, [
                'chat_id' => $chatId,
                'text' => $message,
                'parse_mode' => 'HTML'
            ]);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);

            $result = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            $curlError = curl_error($ch);
            curl_close($ch);

            // Ham response'u döndür
            return $this->asJson([
                'http_code' => $httpCode,
                'curl_error' => $curlError,
                'raw_response' => $result,
                'parsed_response' => json_decode($result, true),
                'request_data' => [
                    'url' => $url,
                    'chat_id' => $chatId,
                    'message' => $message
                ]
            ]);

        } catch (\Exception $e) {
            return $this->asJson([
                'error' => $e->getMessage(),
                'trace' => $e->getTraceAsString()
            ]);
        }
    }

    /**
     * Telegram Updates - Bot'a gelen mesajları görür
     * GET /api/terminal/test-telegram-updates
     */
    public function actionTestTelegramUpdates()
    {
        try {
            $botToken = WMSTelegramNotification::TELEGRAM_BOT_TOKEN;
            $url = "https://api.telegram.org/bot{$botToken}/getUpdates";

            $ch = curl_init();
            curl_setopt($ch, CURLOPT_URL, $url);
            curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch, CURLOPT_TIMEOUT, 10);

            $result = curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);

            $data = json_decode($result, true);
            $chats = [];

            if ($httpCode === 200 && isset($data['result'])) {
                foreach ($data['result'] as $update) {
                    if (isset($update['message']['chat'])) {
                        $chat = $update['message']['chat'];
                        $chats[] = [
                            'chat_id' => $chat['id'],
                            'title' => $chat['title'] ?? 'Private',
                            'type' => $chat['type'],
                            'message' => $update['message']['text'] ?? '',
                            'date' => date('Y-m-d H:i:s', $update['message']['date'] ?? 0)
                        ];
                    }
                    // Channel posts için de kontrol et
                    if (isset($update['channel_post']['chat'])) {
                        $chat = $update['channel_post']['chat'];
                        $chats[] = [
                            'chat_id' => $chat['id'],
                            'title' => $chat['title'] ?? 'Channel',
                            'type' => $chat['type'],
                            'message' => $update['channel_post']['text'] ?? '',
                            'date' => date('Y-m-d H:i:s', $update['channel_post']['date'] ?? 0)
                        ];
                    }
                }
            }

            return $this->asJson([
                'success' => $httpCode === 200,
                'http_code' => $httpCode,
                'found_chats' => $chats,
                'unique_chats' => array_unique(array_column($chats, 'chat_id')),
                'raw_updates_count' => count($data['result'] ?? []),
                'note' => 'Gruba /start veya herhangi bir mesaj yazın ve bu endpoint\'i tekrar çağırın'
            ]);

        } catch (\Exception $e) {
            return $this->asJson([
                'error' => $e->getMessage()
            ]);
        }
    }

    /**
     * Telegram bot test - Hata simülasyonu
     * GET /api/terminal/test-telegram-error
     */
    public function actionTestTelegramError()
    {
        try {
            // Gerçek bir hata senaryosu simüle et
            $result = WMSTelegramNotification::notifyGoodsReceiptError(
                'Test Çalışan',
                'TEST-PO-12345',
                'Bu bir test hata mesajıdır - Sipariş kapalı durumda',
                [
                    'Depo' => 'DEPO-01',
                    'İrsaliye No' => 'IRS-2024-001',
                    'Test' => 'Bu bir test bildirimidir'
                ]
            );

            if ($result) {
                return $this->asJson([
                    'success' => true,
                    'message' => 'Hata bildirimi başarıyla gönderildi! Telegram grubunuzu kontrol edin.'
                ]);
            } else {
                return $this->asJson([
                    'success' => false,
                    'message' => 'Hata bildirimi gönderilemedi.'
                ]);
            }
        } catch (\Exception $e) {
            return $this->asJson([
                'success' => false,
                'error' => $e->getMessage()
            ]);
        }
    }

    public function actionSyncCounts()
    {
        $payload = $this->getJsonBody();
        $warehouseCode = $payload['warehouse_code'] ?? null;
        $lastSyncTimestamp = $payload['last_sync_timestamp'] ?? null;

        if (!$warehouseCode) {
            return $this->errorResponse('Depo kodu (warehouse_code) zorunludur.', 400);
        }
        
        // Get warehouse information from warehouse_code
        $warehouseInfo = (new Query())
            ->select(['id', 'warehouse_code'])
            ->from('warehouses')
            ->where(['warehouse_code' => $warehouseCode])
            ->one();
            
        if (!$warehouseInfo) {
            return $this->errorResponse('Depo bulunamadı.', 400);
        }
        
        $warehouseId = $warehouseInfo['id'];
        if (!$warehouseId) {
            return $this->errorResponse('Depo ID bilgisi bulunamadı.', 400);
        }

        // Buffer timestamp hazırlığı - ana sync ile tutarlı
        $serverSyncTimestamp = $lastSyncTimestamp;
        if ($lastSyncTimestamp) {
            $syncDateTime = new \DateTime($lastSyncTimestamp);
            // Ana sync ile aynı 60 saniye buffer kullan
            $syncDateTime->sub(new \DateInterval('PT60S'));
            $serverSyncTimestamp = $syncDateTime->format('Y-m-d H:i:s');
        }

        try {
            $counts = [];
            
            // Warehouse bilgilerini al
            $warehouseInfo = (new Query())
                ->select(['warehouse_code', 'name', '_key'])
                ->from('warehouses')
                ->where(['id' => $warehouseId])
                ->one();

            if (!$warehouseInfo) {
                throw new \Exception("Warehouse ID $warehouseId bulunamadı.");
            }

            $warehouseCode = $warehouseInfo['warehouse_code'];
            $warehouseKey = $warehouseInfo['_key'];
            
            // Her tablo için count bilgisi
            $counts['urunler'] = $this->getTableCount('urunler', $serverSyncTimestamp);
            
            $counts['tedarikci'] = $this->getTableCount('tedarikci', $serverSyncTimestamp);
            $counts['birimler'] = $this->getTableCount('birimler', $serverSyncTimestamp);
            $counts['barkodlar'] = $this->getTableCount('barkodlar', $serverSyncTimestamp);
            $counts['shelfs'] = $this->getTableCount('shelfs', $serverSyncTimestamp, ['warehouse_id' => $warehouseId]);
            $counts['employees'] = $this->getTableCount('employees', $serverSyncTimestamp, ['warehouse_code' => $warehouseCode]);
            
            // Siparişler için özel sorgu
            $counts['siparisler'] = $this->getOrdersCount($warehouseKey, $serverSyncTimestamp);
            $counts['siparis_ayrintili'] = $this->getOrderLinesCount($warehouseKey, $serverSyncTimestamp);
            
            // Diğer tablolar
            $counts['goods_receipts'] = $this->getGoodsReceiptsCount($warehouseId, $serverSyncTimestamp);
            $counts['goods_receipt_items'] = $this->getGoodsReceiptItemsCount($warehouseId, $serverSyncTimestamp);
            $counts['inventory_stock'] = $this->getInventoryStockCount($warehouseId, $serverSyncTimestamp);
            $counts['inventory_transfers'] = $this->getInventoryTransfersCount($warehouseId, $serverSyncTimestamp);
            // wms_putaway_status tablosu kaldırıldı
            
            // Tombstone kayıtları sayısı
            $counts['wms_tombstones'] = $this->getTombstoneCount($warehouseCode, $serverSyncTimestamp);

            return [
                'success' => true,
                'counts' => $counts,
                'total_records' => array_sum($counts),
                'timestamp' => $this->getCurrentUtcTimestamp()
            ];

        } catch (\Exception $e) {
            $this->logToFile("SyncCounts Hatası: " . $e->getMessage(), 'ERROR');
            return $this->errorResponse('Count sorgusu başarısız: ' . $e->getMessage());
        }
    }

    private function getTableCount($tableName, $timestamp = null, $extraConditions = []) 
    {
        $query = (new Query())->from($tableName);
        
        if ($timestamp) {
            $query->where(['>=', 'updated_at', $timestamp]);
        }

        foreach ($extraConditions as $column => $value) {
            $query->andWhere([$column => $value]);
        }

        return (int)$query->count();
    }

    private function getOrdersCount($warehouseKey, $timestamp = null)
    {
        $query = (new Query())
            ->from('siparisler')
            ->where(['_key_sis_depo_source' => $warehouseKey])
            ->andWhere(['in', 'status', [0, 1, 2]])
            ->andWhere(['turu' => '1']); // Sadece turu=1 olan siparişler

        if ($timestamp) {
            $query->andWhere(['>=', 'updated_at', $timestamp]);
        }

        return (int)$query->count();
    }

    private function getOrderLinesCount($warehouseKey, $timestamp = null)
    {
        $query = (new Query())
            ->from('siparis_ayrintili')
            ->where(['siparis_ayrintili.turu' => '1']); // FIX: Table prefix added

        if ($timestamp) {
            $query->andWhere(['>=', 'siparis_ayrintili.updated_at', $timestamp]); // DÜZELTME: Tablo öneki eklendi
            // Sadece ilgili warehouse'un siparişlerini say
            $query->innerJoin('siparisler', 'siparisler.id = siparis_ayrintili.siparisler_id')
                  ->andWhere(['siparisler._key_sis_depo_source' => $warehouseKey]);
        } else {
            $query->innerJoin('siparisler', 'siparisler.id = siparis_ayrintili.siparisler_id')
                  ->andWhere(['siparisler._key_sis_depo_source' => $warehouseKey]);
        }

        return (int)$query->count();
    }

    private function getGoodsReceiptsCount($warehouseId, $timestamp = null)
    {
        // Use employee-based filtering instead of direct warehouse_id
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);

        $query = (new Query())->from('goods_receipts')->where(['employee_id' => $employeeIds]);
        if ($timestamp) {
            $query->andWhere(['>=', 'updated_at', $timestamp]);
        }
        return (int)$query->count();
    }

    private function getGoodsReceiptItemsCount($warehouseId, $timestamp = null)
    {
        // Use employee-based filtering instead of direct warehouse_id
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);

        $query = (new Query())
            ->from('goods_receipt_items')
            ->innerJoin('goods_receipts', 'goods_receipts.goods_receipt_id = goods_receipt_items.receipt_id')
            ->where(['goods_receipts.employee_id' => $employeeIds]);

        if ($timestamp) {
            $query->andWhere(['>=', 'goods_receipt_items.updated_at', $timestamp]);
        }
        return (int)$query->count();
    }

    private function getInventoryStockCount($warehouseId, $timestamp = null) {
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        if (!$warehouseCode) {
            return 0;
        }
        return $this->getTableCount('inventory_stock', $timestamp, ['warehouse_code' => $warehouseCode]);
    }

    private function getInventoryTransfersCount($warehouseId, $timestamp = null)
    {
        $locationIds = (new Query())->select('id')->from('shelfs')->where(['warehouse_id' => $warehouseId])->column();
        // Use employee-based filtering instead of direct warehouse_id
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);
        $receiptIds = (new Query())->select('goods_receipt_id')->from('goods_receipts')->where(['employee_id' => $employeeIds])->column();

        $query = (new Query())->from('inventory_transfers');
        $conditions = ['or'];

        if (!empty($locationIds)) {
            $conditions[] = ['in', 'from_location_id', $locationIds];
            $conditions[] = ['in', 'to_location_id', $locationIds];
        }
        if (!empty($receiptIds)) {
            $conditions[] = ['in', 'goods_receipt_id', $receiptIds];
        }

        if (count($conditions) > 1) {
            $query->where($conditions);
            if ($timestamp) {
                $query->andWhere(['>=', 'updated_at', $timestamp]);
            }
            return (int)$query->count();
        }
        return 0;
    }

    // wms_putaway_status tablosu kaldırıldı - bu metod artık kullanılmıyor

    private function getTombstoneCount($warehouseCode, $timestamp = null)
    {
        $query = (new Query())
            ->from('wms_tombstones')
            ->where(['warehouse_code' => $warehouseCode]);

        if ($timestamp) {
            $query->andWhere(['>=', 'deleted_at', $timestamp]);
        }

        return (int)$query->count();
    }

    /**
     * Eski tombstone kayıtlarını temizler
     * 7 günden eski tombstone kayıtlarını siler
     */
    private function cleanupOldTombstones($warehouseCode = null, $daysOld = 7)
    {
        $db = Yii::$app->db;
        $cutoffDate = new \DateTime();
        $cutoffDate->sub(new \DateInterval('P' . $daysOld . 'D'));
        $cutoffDateStr = $cutoffDate->format('Y-m-d H:i:s');

        try {
            // UUID tabanlı tombstone tablosundan eski kayıtları temizle
            $deleteConditions = [
                'and',
                ['<', 'deleted_at', $cutoffDateStr],
                ['warehouse_code' => $warehouseCode]
            ];

            $deletedCount = $db->createCommand()
                ->delete('wms_tombstones', $deleteConditions)
                ->execute();

            if ($deletedCount > 0) {
                Yii::info("Tombstone cleanup: $deletedCount old UUID records deleted (older than $daysOld days)", __METHOD__);
            }

            return $deletedCount;

        } catch (\Exception $e) {
            $this->logToFile("Tombstone cleanup error: " . $e->getMessage(), 'ERROR');
            return 0;
        }
    }

    public function actionSyncDownload()
{
    $payload = $this->getJsonBody();
    $warehouseCode = $payload['warehouse_code'] ?? null;
    $lastSyncTimestamp = $payload['last_sync_timestamp'] ?? null;

    // ########## YENİ PAGINATION PARAMETRELERİ ##########
    $tableName = $payload['table_name'] ?? null;
    $page = (int)($payload['page'] ?? 1);
    $limit = (int)($payload['limit'] ?? 5000);

    if (!$warehouseCode) {
        return $this->errorResponse('Depo kodu (warehouse_code) zorunludur.', 400);
    }

    // Get warehouse information from warehouse_code
    $warehouseInfo = (new Query())
        ->select(['id', 'warehouse_code'])
        ->from('warehouses')
        ->where(['warehouse_code' => $warehouseCode])
        ->one();

    if (!$warehouseInfo) {
        return $this->errorResponse('Depo bulunamadı.', 400);
    }

    $warehouseId = $warehouseInfo['id'];
    if (!$warehouseId) {
        return $this->errorResponse('Depo ID bilgisi bulunamadı.', 400);
    }


    // Eğer table_name belirtilmişse, paginated mode
    if ($tableName) {
        return $this->handlePaginatedTableDownload($warehouseId, $lastSyncTimestamp, $tableName, $page, $limit);
    }

    // Eski mod - tüm tabloları birden indir (backward compatibility için)

    // ########## UTC TIMESTAMP KULLANIMI ##########
    // Global kullanım için UTC timestamp'leri direkt karşılaştır
    $serverSyncTimestamp = $lastSyncTimestamp;

    // GÜVENLIK: Race condition ve timing sorunları için 60 saniye buffer ekle
    if ($lastSyncTimestamp) {
        // ISO8601 formatını parse et (2025-08-22T21:20:28.545772Z)
        $syncDateTime = new \DateTime($lastSyncTimestamp);
        // Race condition riskini minimize etmek için buffer artırıldı
        $syncDateTime->sub(new \DateInterval('PT60S')); // 30'dan 60 saniyeye çıkarıldı
        $serverSyncTimestamp = $syncDateTime->format('Y-m-d H:i:s');

        // Debug için log
        \Yii::info("Sync buffer applied: original={$lastSyncTimestamp}, buffered={$serverSyncTimestamp}", __METHOD__);
    } else {
    }

    try {
        $data = [];

        // Timestamp hazır, direkt kullan

        // ########## İNKREMENTAL SYNC İÇİN ÜRÜNLER ##########
        // ESKİ BARCODE ALANLARI ARTIK KULLANILMIYOR - Yeni barkodlar tablosuna geçildi
        // TODO: UrunId yerine _key kullanılacak - _key eşsiz ürün tanımlayıcısı
        try {
            $urunlerQuery = (new Query())
                ->select(['UrunId as id', 'StokKodu', 'UrunAdi', 'aktif', '_key', 'updated_at'])
                ->from('urunler');

            // Eğer last_sync_timestamp varsa, sadece o tarihten sonra güncellenen ürünleri al
            if ($serverSyncTimestamp) {
                $urunlerQuery->where(['>=', 'updated_at', $serverSyncTimestamp]);
            } else {
                // İlk sync ise tüm ürünleri al (aktif/pasif ayrımı olmadan)
                // Mobil uygulama kendi filtrelemesini yapar
            }

            // DÜZELTME: Tüm ürünleri gönder (aktif=0 olanlar da dahil)
            // Mobil uygulama WHERE u.aktif = 1 filtresi kullanıyor, bu nedenle
            // server'dan aktif=0 olanlar da gelmeli ki mobil tarafta doğru çalışsın

            $urunlerData = $urunlerQuery->all();
            $this->applyStandardCasts($urunlerData, 'urunler');
            $data['urunler'] = $urunlerData;

        } catch (\Exception $e) {
            $this->logToFile("Ürünler tablosu hatası: " . $e->getMessage(), 'ERROR');
            throw new \Exception("Ürünler tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## İNKREMENTAL SYNC BİTTİ ##########

        // ########## TEDARİKÇİ İÇİN İNKREMENTAL SYNC ##########
        try {
            $tedarikciQuery = (new Query())
                ->select(['id', 'tedarikci_kodu', 'tedarikci_adi', 'Aktif', 'updated_at'])
                ->from('tedarikci');

            // Eğer last_sync_timestamp varsa, sadece o tarihten sonra güncellenen tedarikçileri al
            if ($serverSyncTimestamp) {
                $tedarikciQuery->where(['>=', 'updated_at', $serverSyncTimestamp]);
            } else {
                // İlk sync ise tüm tedarikçileri al
            }

            $tedarikciData = $tedarikciQuery->all();
            $this->applyStandardCasts($tedarikciData, 'tedarikci');
            $data['tedarikci'] = $tedarikciData;

        } catch (\Exception $e) {
            $this->logToFile("Tedarikçi tablosu hatası: " . $e->getMessage(), 'ERROR');
            throw new \Exception("Tedarikçi tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## TEDARİKÇİ İNKREMENTAL SYNC BİTTİ ##########

        // ########## BİRİMLER İÇİN İNKREMENTAL SYNC ##########
        try {
            $birimlerQuery = (new Query())
                ->select(['id', 'birimadi', 'birimkod', '_key', '_key_scf_stokkart', 'StokKodu',
                         'created_at', 'updated_at'])
                ->from('birimler');

            if ($serverSyncTimestamp) {
                $birimlerQuery->where(['>=', 'updated_at', $serverSyncTimestamp]);
            } else {
            }

            $birimlerData = $birimlerQuery->all();
            $this->castNumericValues($birimlerData, ['id'], []);
            $data['birimler'] = $birimlerData;

        } catch (\Exception $e) {
            $this->logToFile("Birimler tablosu hatası: " . $e->getMessage(), 'ERROR');
            throw new \Exception("Birimler tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## BİRİMLER İNKREMENTAL SYNC BİTTİ ##########

        // ########## BARKODLAR İÇİN İNKREMENTAL SYNC ##########
        try {
            $barkodlarQuery = (new Query())
                ->select(['id', '_key', '_key_scf_stokkart_birimleri', 'barkod', 'turu', 'created_at', 'updated_at'])
                ->from('barkodlar');

            if ($serverSyncTimestamp) {
                $barkodlarQuery->where(['>=', 'updated_at', $serverSyncTimestamp]);
            } else {
            }

            $barkodlarData = $barkodlarQuery->all();
            $this->castNumericValues($barkodlarData, ['id']);
            $data['barkodlar'] = $barkodlarData;

        } catch (\Exception $e) {
            $this->logToFile("Barkodlar tablosu hatası: " . $e->getMessage(), 'ERROR');
            throw new \Exception("Barkodlar tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## BARKODLAR İNKREMENTAL SYNC BİTTİ ##########

        // ########## SHELFS İÇİN İNKREMENTAL SYNC ##########
        $shelfsQuery = (new Query())
            ->select(['id', 'warehouse_id', 'name', 'code', 'is_active', 'created_at', 'updated_at'])
            ->from('shelfs')
            ->where(['warehouse_id' => $warehouseId]);
        if ($serverSyncTimestamp) {
            $shelfsQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        } else {
        }
        $data['shelfs'] = $shelfsQuery->all();
        $this->applyStandardCasts($data['shelfs'], 'shelfs');

        // warehouse tablosu kaldırıldı - mobil uygulama SharedPreferences kullanıyor

        // ########## ROWHUB'A ÖZEL UYARLAMA BAŞLIYOR ##########

        // 1. Gelen warehouseId'ye ait warehouse bilgilerini buluyoruz.
        $warehouseInfo = (new Query())
            ->select(['warehouse_code', 'name', '_key'])
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->one();

        if (!$warehouseInfo) {
            throw new \Exception("Warehouse ID $warehouseId bulunamadı. Siparişler indirilemiyor.");
        }

        $warehouseCode = $warehouseInfo['warehouse_code'];
        $warehouseName = $warehouseInfo['name'];
        $warehouseKey = $warehouseInfo['_key'];

        // ########## EMPLOYEES İÇİN İNKREMENTAL SYNC ##########
        // Rowhub formatında employee sorgusu - warehouse_code kullanılıyor
        $employeeColumns = [
            'e.id', 'e.first_name', 'e.last_name', 'e.username', 'e.password',
            'e.warehouse_code', 'e.role', 'e.is_active', 'e.created_at', 'e.updated_at'
        ];
        $employeesQuery = (new Query())
            ->select($employeeColumns)
            ->from(['e' => 'employees'])
            ->where(['e.is_active' => 1, 'e.warehouse_code' => $warehouseCode]);

        if ($serverSyncTimestamp) {
            $employeesQuery->andWhere(['>=', 'e.updated_at', $serverSyncTimestamp]);
        } else {
        }
        $data['employees'] = $employeesQuery->all();
        $this->applyStandardCasts($data['employees'], 'employees');

        // 2. Siparişleri warehouse _key ile eşleştiriyoruz.
        // Optimize edilmiş alanları seç - gereksiz alanlar kaldırıldı
        $poQuery = (new Query())
            ->select([
                'id', 'fisno', 'tarih', 'status',
                '_key_sis_depo_source', '__carikodu', 'created_at', 'updated_at'
            ])
            ->from('siparisler')
            ->where(['_key_sis_depo_source' => $warehouseKey])
            ->andWhere(['in', 'status', [0, 1, 2]]) // Aktif durumlar
            ->andWhere(['turu' => '1']); // Sadece turu=1 olan siparişler

        // ########## SATIN ALMA SİPARİS FİŞ İÇİN İNKREMENTAL SYNC ##########
        if ($serverSyncTimestamp) {
            $poQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        } else {
        }

        $data['siparisler'] = $poQuery->all();

        // notlar alanını null olarak ekle çünkü server DB'de yok ama client'da kullanılıyor
        foreach ($data['siparisler'] as &$siparis) {
            $siparis['notlar'] = null;
        }
        // ########## UYARLAMA BİTTİ ##########


        // DEBUG: Sipariş olmadığında debug bilgisi
        if (empty($data['siparisler'])) {
            $allOrdersQuery = (new Query())->select(['count(*) as total'])->from('siparisler');
            $allOrdersCount = $allOrdersQuery->scalar();

            $ordersWithKeyQuery = (new Query())->select(['count(*) as total'])->from('siparisler')->where(['_key_sis_depo_source' => $warehouseKey]);
            $ordersWithKeyCount = $ordersWithKeyQuery->scalar();

            // Eğer _key_sis_depo_source sütunu yoksa hata atacak
            try {
                $sampleOrderQuery = (new Query())->select(['id', '_key_sis_depo_source'])->from('siparisler')->limit(5);
                $sampleOrders = $sampleOrderQuery->all();
            } catch (\Exception $e) {
            }
        }

        $this->castNumericValues($data['siparisler'], ['id', 'status']); // `branch_id` artık bu tabloda olmadığı için cast'ten çıkarıldı.

        // Fonksiyonun geri kalanı aynı, çünkü diğer tablolarımız zaten uyumlu.
        $poIds = array_column($data['siparisler'], 'id');

        $data['siparis_ayrintili'] = [];
        // wms_putaway_status tablosu kaldırıldı
        $data['goods_receipts'] = [];
        $data['goods_receipt_items'] = [];

        if (!empty($poIds)) {
            // ########## SATIN ALMA SİPARİS FİŞ SATIR İÇİN İNKREMENTAL SYNC ##########
            $poLineQuery = (new Query())
                ->select([
                    'sa.id', 'sa.siparisler_id', 'sa.kartkodu', 'sa.miktar',
                    'sa.created_at', 'sa.updated_at', 'sa.status', 'sa.turu',
                    'sa._key_kalemturu'
                ])
                ->from(['sa' => 'siparis_ayrintili'])
                ->where(['in', 'sa.siparisler_id', $poIds])
                ->andWhere(['sa.turu' => '1']); // DÜZELTME: Tablo öneki eklendi
            if ($serverSyncTimestamp) {
                $poLineQuery->andWhere(['>=', 'sa.updated_at', $serverSyncTimestamp]); // DÜZELTME: Tablo öneki eklendi
            } else {
            }
            $data['siparis_ayrintili'] = $poLineQuery->all();
            $this->castNumericValues($data['siparis_ayrintili'], ['id', 'siparisler_id', 'status'], ['miktar']);

            $poLineIds = array_column($data['siparis_ayrintili'], 'id');
            if (!empty($poLineIds)) {
                // wms_putaway_status tablosu kaldırıldı - putaway durumu inventory_stock'tan takip ediliyor
            }

            // ########## GOODS RECEIPTS İÇİN İNKREMENTAL SYNC ##########
            $poReceiptsQuery = (new Query())->select(['goods_receipt_id as id', 'operation_unique_id', 'siparis_id', 'invoice_number', 'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])->from('goods_receipts')->where(['in', 'siparis_id', $poIds]);
            if ($serverSyncTimestamp) {
                $poReceiptsQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
            }
            $poReceipts = $poReceiptsQuery->all();
            $data['goods_receipts'] = $poReceipts;
            $this->castNumericValues($data['goods_receipts'], ['id', 'siparis_id', 'employee_id']);
        }

        // ########## FREE RECEIPTS İÇİN İNKREMENTAL SYNC ##########
        // Use employee-based filtering instead of direct warehouse_id
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);
        $freeReceiptsQuery = (new Query())->select(['goods_receipt_id as id', 'operation_unique_id', 'siparis_id', 'invoice_number', 'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])->from('goods_receipts')->where(['siparis_id' => null]);
        if (!empty($employeeIds)) {
            $freeReceiptsQuery->andWhere(['in', 'employee_id', $employeeIds]);
        } else {
            $freeReceiptsQuery->where('1=0'); // No employees found, return empty
        }
        if ($serverSyncTimestamp) {
            $freeReceiptsQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }
        $freeReceipts = $freeReceiptsQuery->all();
        $data['goods_receipts'] = $this->mergeArraysSafely($data['goods_receipts'], $freeReceipts);

        $this->applyStandardCasts($data['goods_receipts'], 'goods_receipts');

        // ########## GOODS RECEIPT ITEMS İÇİN İNKREMENTAL SYNC ##########
        $receiptIds = array_column($data['goods_receipts'], 'id');
        if (!empty($receiptIds)) {
            $receiptItemsQuery = (new Query())
                ->select(['id', 'receipt_id', 'operation_unique_id', 'item_uuid', 'urun_key', 'birim_key', 'siparis_key', 'quantity_received', 'pallet_barcode', 'barcode', 'expiry_date', 'free', 'created_at', 'updated_at'])
                ->from('goods_receipt_items')
                ->where(['in', 'receipt_id', $receiptIds]);
            if ($serverSyncTimestamp) {
                $receiptItemsQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
            }
            $data['goods_receipt_items'] = $receiptItemsQuery->all();
            $this->castNumericValues($data['goods_receipt_items'], ['id', 'receipt_id'], ['quantity_received']);
        }

        // ########## INVENTORY STOCK İÇİN İNKREMENTAL SYNC ##########
        $locationIds = array_column($data['shelfs'], 'id');
        $stockQuery = (new Query())
            ->select(['id', 'stock_uuid', 'urun_key', 'birim_key', 'location_id', 'siparis_id', 'goods_receipt_id', 'quantity', 'pallet_barcode', 'expiry_date', 'stock_status', 'created_at', 'updated_at'])
            ->from('inventory_stock');
        $stockConditions = ['or'];

        if (!empty($locationIds)) {
            $stockConditions[] = ['in', 'location_id', $locationIds];
        }

        // Use employee-based filtering instead of direct warehouse_id
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);
        $allReceiptIdsForWarehouse = (new Query())
            ->select('goods_receipt_id')
            ->from('goods_receipts')
            ->where(['employee_id' => $employeeIds])
            ->column();

        if (!empty($allReceiptIdsForWarehouse)) {
            $stockConditions[] = [
                'and',
                ['is', 'location_id', new \yii\db\Expression('NULL')],
                ['in', 'goods_receipt_id', $allReceiptIdsForWarehouse]
            ];
        }

        if (count($stockConditions) > 1) {
            $stockQuery->where($stockConditions);
            // İnkremental sync için updated_at filtresi
            if ($serverSyncTimestamp) {
                $stockQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
            }
        } else {
            $stockQuery->where('1=0');
        }

        $data['inventory_stock'] = $stockQuery->all();
         $this->applyStandardCasts($data['inventory_stock'], 'inventory_stock');

        // ########## INVENTORY TRANSFERS İÇİN İNKREMENTAL SYNC ##########
        $transferQuery = (new Query())
            ->select(['id', 'urun_key', 'birim_key', 'from_location_id', 'to_location_id', 'quantity', 'from_pallet_barcode', 'pallet_barcode', 'siparis_id', 'goods_receipt_id', 'delivery_note_number', 'employee_id', 'transfer_date', 'created_at', 'updated_at'])
            ->from('inventory_transfers');
        $transferConditions = ['or'];

        // Warehouse'a ait location'lardan/location'lara yapılan transferler
        if (!empty($locationIds)) {
            $transferConditions[] = ['in', 'from_location_id', $locationIds];
            $transferConditions[] = ['in', 'to_location_id', $locationIds];
        }

        // Warehouse'a ait goods_receipt'lerle ilgili transferler
        if (!empty($allReceiptIdsForWarehouse)) {
            $transferConditions[] = ['in', 'goods_receipt_id', $allReceiptIdsForWarehouse];
        }

        if (count($transferConditions) > 1) {
            $transferQuery->where($transferConditions);
            // İnkremental sync için updated_at filtresi
            if ($serverSyncTimestamp) {
                $transferQuery->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
            }
        } else {
            $transferQuery->where('1=0');
        }

        $data['inventory_transfers'] = $transferQuery->all();
        $this->castNumericValues($data['inventory_transfers'], ['id', 'from_location_id', 'to_location_id', 'employee_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);

        // ########## TOMBSTONE RECORDS - Silinmiş inventory_stock kayıtları (UUID TABANLI) ##########
        $tombstoneUuids = [];
        if ($serverSyncTimestamp) {
            // Sadece son sync'ten sonra silinmiş kayıtların UUID'lerini al
            $tombstoneQuery = (new Query())
                ->select(['stock_uuid'])
                ->from('wms_tombstones')
                ->andWhere(['>=', 'deleted_at', $serverSyncTimestamp]);

            $tombstoneUuids = $tombstoneQuery->column();

            if (!empty($tombstoneUuids)) {
                Yii::info("TOMBSTONE: Sending " . count($tombstoneUuids) . " deleted inventory_stock UUIDs to mobile", __METHOD__);
            }
        }

        // TOMBSTONE CLEANUP: Eski tombstone kayıtlarını temizle (7 günden eski)
        $this->cleanupOldTombstones($warehouseCode, 7);

        $result = [
            'success' => true,
            'data' => $data,
            'timestamp' => $this->getCurrentUtcTimestamp(),
            'stats' => [
                'urunler_count' => count($data['urunler'] ?? []),
                'tedarikci_count' => count($data['tedarikci'] ?? []),
                'birimler_count' => count($data['birimler'] ?? []),
                'barkodlar_count' => count($data['barkodlar'] ?? []),
                'inventory_stock_count' => count($data['inventory_stock'] ?? []),
                'inventory_transfers_count' => count($data['inventory_transfers'] ?? []),
                'wms_tombstones_count' => count($tombstoneUuids),
                'is_incremental' => !empty($lastSyncTimestamp),
                'last_sync_timestamp' => $lastSyncTimestamp
            ]
        ];

        // UUID tabanlı tombstone listesini ekle
        if (!empty($tombstoneUuids)) {
            $result['wms_tombstones'] = $tombstoneUuids;
        }

        return $result;

    } catch (\Exception $e) {
        $this->logToFile("SyncDownload Hatası: " . $e->getMessage() . "\nTrace: " . $e->getTraceAsString(), 'ERROR');
        return $this->errorResponse('Veritabanı indirme sırasında bir hata oluştu: ' . $e->getMessage());
    }
}

    /**
     * Tek bir tablonun sayfalı verisini indirir
     */
    private function handlePaginatedTableDownload($warehouseId, $lastSyncTimestamp, $tableName, $page, $limit)
    {
        // UTC timestamp hazırlama - buffer ile tutarlı
        $serverSyncTimestamp = $lastSyncTimestamp;
        if ($lastSyncTimestamp) {
            $syncDateTime = new \DateTime($lastSyncTimestamp);
            // Ana sync ile aynı buffer kullan
            $syncDateTime->sub(new \DateInterval('PT60S')); // 60 saniye buffer
            $serverSyncTimestamp = $syncDateTime->format('Y-m-d H:i:s');
        }

        $offset = ($page - 1) * $limit;

        try {
            $data = [];

            switch ($tableName) {
                case 'urunler':
                    $data = $this->getPaginatedUrunler($serverSyncTimestamp, $offset, $limit);
                    break;
                case 'tedarikci':
                    $data = $this->getPaginatedTedarikci($serverSyncTimestamp, $offset, $limit);
                    break;
                case 'birimler':
                    $data = $this->getPaginatedBirimler($serverSyncTimestamp, $offset, $limit);
                    break;
                case 'barkodlar':
                    $data = $this->getPaginatedBarkodlar($serverSyncTimestamp, $offset, $limit);
                    break;
                case 'employees':
                    $data = $this->getPaginatedEmployees($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'shelfs':
                    $data = $this->getPaginatedShelfs($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'siparisler':
                    $data = $this->getPaginatedSiparisler($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'siparis_ayrintili':
                    $data = $this->getPaginatedSiparisAyrintili($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'goods_receipts':
                    $data = $this->getPaginatedGoodsReceipts($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'goods_receipt_items':
                    $data = $this->getPaginatedGoodsReceiptItems($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'inventory_stock':
                    $data = $this->getPaginatedInventoryStock($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                case 'inventory_transfers':
                    $data = $this->getPaginatedInventoryTransfers($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                // wms_putaway_status tablosu kaldırıldı
                case 'wms_tombstones':
                    $data = $this->getPaginatedTombstones($warehouseId, $serverSyncTimestamp, $offset, $limit);
                    break;
                default:
                    throw new \Exception("Desteklenmeyen tablo: $tableName");
            }

            return [
                'success' => true,
                'data' => [$tableName => $data],
                'pagination' => [
                    'table_name' => $tableName,
                    'page' => $page,
                    'limit' => $limit,
                    'count' => count($data)
                ]
            ];
        } catch (\Exception $e) {
            $this->logToFile("Paginated download hatası ($tableName): " . $e->getMessage(), 'ERROR');
            return $this->errorResponse("$tableName tablosu sayfa $page indirilemedi: " . $e->getMessage());
        }
    }

    public function actionHealthCheck()
    {
        return ['status' => 'ok', 'timestamp' => date('c')];
    }

    /**
     * Bilinmeyen barkodları topla ve veritabanına kaydet
     * POST /terminal/unknown-barcodes-upload
     * Payload: { "unknown_barcodes": [ { "barcode": "...", "employee_id": 123, "warehouse_code": "...", "scanned_at": "..." } ] }
     */
    public function actionUnknownBarcodesUpload()
    {
        $payload = $this->getJsonBody();
        $unknownBarcodes = $payload['unknown_barcodes'] ?? [];

        if (empty($unknownBarcodes)) {
            return ['success' => true, 'message' => 'Gönderilecek barkod yok.', 'saved_count' => 0];
        }

        $db = \Yii::$app->db;
        $savedCount = 0;
        $errors = [];

        try {
            foreach ($unknownBarcodes as $item) {
                $barcode = $item['barcode'] ?? null;
                $employeeId = $item['employee_id'] ?? null;
                $warehouseCode = $item['warehouse_code'] ?? null;
                $scannedAt = $item['scanned_at'] ?? null;

                // Barcode zorunlu
                if (!$barcode) {
                    $errors[] = 'Barkod eksik';
                    continue;
                }

                try {
                    // wms_unknown_barcodes tablosuna kaydet
                    $db->createCommand()->insert('wms_unknown_barcodes', [
                        'barcode' => $barcode,
                        'employee_id' => $employeeId,
                        'warehouse_code' => $warehouseCode,
                        'scanned_at' => $scannedAt ? $this->convertIso8601ToMysqlDatetime($scannedAt) : new \yii\db\Expression('NOW()'),
                        'created_at' => new \yii\db\Expression('NOW()'),
                    ])->execute();

                    $savedCount++;
                } catch (\Exception $e) {
                    $errors[] = "Barkod kayıt hatası ($barcode): " . $e->getMessage();
                    $this->logToFile("Unknown barcode save error: " . $e->getMessage(), 'ERROR');
                }
            }

            $response = [
                'success' => true,
                'message' => "$savedCount barkod başarıyla kaydedildi.",
                'saved_count' => $savedCount,
            ];

            if (!empty($errors)) {
                $response['errors'] = $errors;
            }

            return $response;

        } catch (\Exception $e) {
            $this->logToFile("Unknown barcodes upload error: " . $e->getMessage(), 'ERROR');
            return $this->errorResponse('Barkod kayıt işlemi başarısız: ' . $e->getMessage());
        }
    }

    // ########## PAGINATED QUERY METHODS ##########

    private function getPaginatedUrunler($serverSyncTimestamp, $offset, $limit)
    {
        // TODO: UrunId yerine _key kullanılacak - _key eşsiz ürün tanımlayıcısı
        $query = (new Query())
            ->select(['UrunId as id', 'StokKodu', 'UrunAdi', 'aktif', '_key', 'updated_at'])
            ->from('urunler');

        if ($serverSyncTimestamp) {
            $query->where(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);
        $data = $query->all();
        $this->castNumericValues($data, ['id', 'aktif']);
        return $data;
    }

    private function getPaginatedTedarikci($serverSyncTimestamp, $offset, $limit)
    {
        $query = (new Query())
            ->select(['id', 'tedarikci_kodu', 'tedarikci_adi', 'Aktif', 'updated_at'])
            ->from('tedarikci');

        if ($serverSyncTimestamp) {
            $query->where(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);
        $data = $query->all();
        $this->castNumericValues($data, ['id', 'Aktif']);
        return $data;
    }

    private function getPaginatedBirimler($serverSyncTimestamp, $offset, $limit)
    {
        $query = (new Query())
            ->select(['id', 'birimadi', 'birimkod', '_key', '_key_scf_stokkart', 'StokKodu',
                     'created_at', 'updated_at'])
            ->from('birimler');

        if ($serverSyncTimestamp) {
            $query->where(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id'], []);
        return $data;
    }

    private function getPaginatedBarkodlar($serverSyncTimestamp, $offset, $limit)
    {
        $query = (new Query())
            ->select(['id', '_key', '_key_scf_stokkart_birimleri', 'barkod', 'turu', 'created_at', 'updated_at'])
            ->from('barkodlar');

        if ($serverSyncTimestamp) {
            $query->where(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id']);
        return $data;
    }

    private function getPaginatedEmployees($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // Get warehouse info
        $warehouseInfo = (new Query())
            ->select(['warehouse_code'])
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->one();

        if (!$warehouseInfo) {
            throw new \Exception("Warehouse ID $warehouseId bulunamadı.");
        }

        $warehouseCode = $warehouseInfo['warehouse_code'];

        $query = (new Query())
            ->select(['e.id', 'e.first_name', 'e.last_name', 'e.username', 'e.password',
                     'e.warehouse_code', 'e.role', 'e.is_active', 'e.created_at', 'e.updated_at'])
            ->from(['e' => 'employees'])
            ->where(['e.is_active' => 1, 'e.warehouse_code' => $warehouseCode]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'e.updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'is_active']);
        return $data;
    }

    private function getPaginatedShelfs($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        $query = (new Query())
            ->select(['id', 'warehouse_id', 'name', 'code', 'is_active', 'created_at', 'updated_at'])
            ->from('shelfs')
            ->where(['warehouse_id' => $warehouseId]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'warehouse_id', 'is_active']);
        return $data;
    }

    private function getPaginatedSiparisler($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // Get warehouse info
        $warehouseInfo = (new Query())
            ->select(['warehouse_code', 'name', '_key'])
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->one();

        if (!$warehouseInfo) {
            throw new \Exception("Warehouse ID $warehouseId bulunamadı.");
        }

        $warehouseKey = $warehouseInfo['_key'];

        $query = (new Query())
            ->select(['id', 'fisno', 'tarih', 'status',
                     '_key_sis_depo_source', '__carikodu', 'created_at', 'updated_at'])
            ->from('siparisler')
            ->where(['_key_sis_depo_source' => $warehouseKey])
            ->andWhere(['in', 'status', [0, 1, 2]])
            ->andWhere(['turu' => '1']); // Sadece turu=1 olan siparişler

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();

        // Add notlar field as null
        foreach ($data as &$siparis) {
            $siparis['notlar'] = null;
        }

        $this->castNumericValues($data, ['id', 'status']);
        return $data;
    }

    private function getPaginatedSiparisAyrintili($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // First get all order IDs for this warehouse
        $warehouseInfo = (new Query())
            ->select(['_key'])
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->one();

        if (!$warehouseInfo) {
            return [];
        }

        $poIds = (new Query())
            ->select('id')
            ->from('siparisler')
            ->where(['_key_sis_depo_source' => $warehouseInfo['_key']])
            ->andWhere(['in', 'status', [0, 1, 2]])
            ->column();

        if (empty($poIds)) {
            return [];
        }

        $query = (new Query())
            ->select(['sa.id', 'sa.siparisler_id', 'sa.kartkodu', 'sa.miktar',
                     'sa.sipbirimi', 'sa.sipbirimkey', 'sa.created_at', 'sa.updated_at', 'sa.status', 'sa.turu',
                     'sa._key_kalemturu'])
            ->from(['sa' => 'siparis_ayrintili'])
            ->where(['in', 'sa.siparisler_id', $poIds])
            ->andWhere(['sa.turu' => '1']); // FIX: Table prefix added

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'sa.updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'siparisler_id', 'status'], ['miktar']);
        return $data;
    }

    private function getPaginatedGoodsReceipts($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // Get both order-based and free receipts
        $warehouseInfo = (new Query())
            ->select(['_key'])
            ->from('warehouses')
            ->where(['id' => $warehouseId])
            ->one();

        $conditions = ['or'];

        // Order-based receipts
        if ($warehouseInfo) {
            $poIds = (new Query())
                ->select('id')
                ->from('siparisler')
                ->where(['_key_sis_depo_source' => $warehouseInfo['_key']])
                ->column();

            if (!empty($poIds)) {
                $conditions[] = ['in', 'siparis_id', $poIds];
            }
        }

        // Free receipts: Filter by employee warehouse instead of direct warehouse_id
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);

        if (!empty($employeeIds)) {
            $conditions[] = ['and', ['siparis_id' => null], ['in', 'employee_id', $employeeIds]];
        }

        $query = (new Query())
            ->select(['goods_receipt_id as id', 'siparis_id', 'invoice_number',
                     'delivery_note_number', 'employee_id', 'receipt_date', 'operation_unique_id', 'created_at', 'updated_at'])
            ->from('goods_receipts');

        if (count($conditions) > 1) {
            $query->where($conditions);
        } else {
            return [];
        }

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'siparis_id', 'employee_id']);
        return $data;
    }

    private function getPaginatedGoodsReceiptItems($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // Get receipt IDs for this warehouse first
        $receiptIds = $this->getReceiptIdsForWarehouse($warehouseId);

        if (empty($receiptIds)) {
            return [];
        }

        $query = (new Query())
            ->select(['id', 'receipt_id', 'operation_unique_id', 'item_uuid', 'urun_key', 'birim_key', 'siparis_key', 'quantity_received', 'pallet_barcode', 'barcode', 'expiry_date', 'free', 'created_at', 'updated_at'])
            ->from('goods_receipt_items')
            ->where(['in', 'receipt_id', $receiptIds]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'receipt_id'], ['quantity_received']);
        return $data;
    }

    private function getPaginatedInventoryStock($warehouseId, $serverSyncTimestamp, $offset, $limit) {
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        if (!$warehouseCode) {
            return [];
        }
        $query = (new Query())
            ->select(['id', 'stock_uuid', 'urun_key', 'birim_key', 'location_id', 'siparis_id', 'goods_receipt_id', 'quantity', 'pallet_barcode', 'expiry_date', 'stock_status', 'created_at', 'updated_at'])
            ->from('inventory_stock')
            ->where(['warehouse_code' => $warehouseCode]);
        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }
        $query->offset($offset)->limit($limit);
        $data = $query->all();
        $this->castNumericValues($data, ['id', 'location_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);
        return $data;
    }

    private function getPaginatedInventoryTransfers($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        $locationIds = (new Query())
            ->select('id')
            ->from('shelfs')
            ->where(['warehouse_id' => $warehouseId])
            ->column();

        $allReceiptIds = $this->getReceiptIdsForWarehouse($warehouseId);

        $transferConditions = ['or'];

        if (!empty($locationIds)) {
            $transferConditions[] = ['in', 'from_location_id', $locationIds];
            $transferConditions[] = ['in', 'to_location_id', $locationIds];
        }

        if (!empty($allReceiptIds)) {
            $transferConditions[] = ['in', 'goods_receipt_id', $allReceiptIds];
        }

        if (count($transferConditions) <= 1) {
            return [];
        }

        $query = (new Query())
            ->select(['id', 'urun_key', 'birim_key', 'from_location_id', 'to_location_id', 'quantity', 'from_pallet_barcode', 'pallet_barcode', 'siparis_id', 'goods_receipt_id', 'delivery_note_number', 'employee_id', 'transfer_date', 'created_at', 'updated_at'])
            ->from('inventory_transfers')
            ->where($transferConditions);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'from_location_id', 'to_location_id', 'employee_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);
        return $data;
    }

    // wms_putaway_status tablosu kaldırıldı - bu metod artık kullanılmıyor

    private function getPaginatedTombstones($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // Get warehouse code
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        if (!$warehouseCode) {
            return [];
        }

        $query = (new Query())
            ->select(['stock_uuid'])
            ->from('wms_tombstones')
            ->where(['warehouse_code' => $warehouseCode]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>=', 'deleted_at', $serverSyncTimestamp]);
        }
        
        $query->offset($offset)->limit($limit);
        
        // Return UUIDs as array, not as objects
        return $query->column();
    }

    // Helper method to get receipt IDs for a warehouse
    private function getReceiptIdsForWarehouse($warehouseId)
    {
        // Use employee-based filtering instead of direct warehouse_id
        $warehouseCode = $this->getWarehouseCodeById($warehouseId);
        $employeeIds = $this->getEmployeeIdsByWarehouseCode($warehouseCode);
        return (new Query())
            ->select('goods_receipt_id')
            ->from('goods_receipts')
            ->where(['employee_id' => $employeeIds])
            ->column();
    }

    public function actionSyncShelfs()
    {
        $result = DepoComponent::syncWarehousesAndShelfs();
        return $this->asJson($result);
    }


    public function actionGetFreeReceiptsForPutaway()
    {
        $params = $this->getJsonBody();
        $employeeId = $params['employee_id'] ?? null;

        if ($employeeId === null) {
            return ['success' => false, 'message' => 'Çalışan ID (employee_id) zorunludur.'];
        }
        
        // Get warehouse information from employee
        $employeeInfo = (new Query())
            ->select(['e.warehouse_code', 'w.id'])
            ->from(['e' => 'employees'])
            ->leftJoin(['w' => 'warehouses'], 'e.warehouse_code = w.warehouse_code')
            ->where(['e.id' => $employeeId])
            ->one();
            
        if (!$employeeInfo) {
            return ['success' => false, 'message' => 'Çalışan bulunamadı.'];
        }
        
        $warehouseId = $employeeInfo['id'];
        if (!$warehouseId) {
            return ['success' => false, 'message' => 'Çalışanın depo bilgisi bulunamadı.'];
        }

        $query = new Query();
        $receipts = $query->select([
                'gr.goods_receipt_id as goods_receipt_id',
                'gr.delivery_note_number',
                'gr.receipt_date',
                'e.first_name',
                'e.last_name',
                'COUNT(DISTINCT ist.urun_key) as item_count'
            ])
            ->from('goods_receipts gr')
            ->innerJoin('inventory_stock ist', 'ist.goods_receipt_id = gr.goods_receipt_id')
            ->innerJoin('employees e', 'e.id = gr.employee_id')
            ->where(['gr.siparis_id' => null])
            ->andWhere(['ist.stock_status' => 'receiving'])
            ->andWhere(['gr.employee_id' => (new Query())->select('id')->from('employees')->where(['warehouse_code' => (new Query())->select('warehouse_code')->from('warehouses')->where(['id' => $warehouseId])->scalar()])->column()])
            ->groupBy(['gr.goods_receipt_id', 'gr.delivery_note_number', 'gr.receipt_date', 'e.first_name', 'e.last_name'])
            ->orderBy(['gr.receipt_date' => SORT_DESC])
            ->all();

        return ['success' => true, 'data' => $receipts];
    }

    /**
     * Save warehouse count (for "Save & Continue" feature)
     * Endpoint: POST /terminal/warehouse-count-save
     */
    public function actionWarehouseCountSave()
    {
        $data = $this->getJsonBody();

        if (empty($data['header']) || empty($data['items'])) {
            return [
                'status' => 400,
                'message' => 'Geçersiz veri: header ve items zorunludur.'
            ];
        }

        // _createWarehouseCount metodunu kullan
        $db = Yii::$app->db;
        $result = $this->_createWarehouseCount([
            'header' => $data['header'],
            'items' => $data['items']
        ], $db);

        if ($result['status'] === 'success') {
            return [
                'status' => 200,
                'message' => $result['message'],
                'count_sheet_id' => $result['count_sheet_id']
            ];
        } else {
            return [
                'status' => 400,
                'message' => $result['message']
            ];
        }
    }

    /**
     * Telegram log file endpoint
     * Flutter'dan gelen hata loglarını TXT dosyası olarak Telegram'a gönderir
     * Endpoint: POST /terminal/telegram-log-file
     */
    public function actionTelegramLogFile()
    {
        $data = $this->getJsonBody();

        if (empty($data['title']) || empty($data['log_content'])) {
            return [
                'status' => 400,
                'message' => 'Geçersiz veri: title ve log_content zorunludur.'
            ];
        }

        try {
            $title = $data['title'];
            $logContent = $data['log_content'];
            $deviceInfo = $data['device_info'] ?? [];
            $employeeName = $data['employee_name'] ?? null;

            // Telegram'a dosya gönder
            $success = WMSTelegramNotification::sendLogFile(
                $title,
                $logContent,
                $deviceInfo,
                $employeeName
            );

            if ($success) {
                return [
                    'status' => 200,
                    'message' => 'Log dosyası Telegram\'a başarıyla gönderildi.'
                ];
            } else {
                return [
                    'status' => 500,
                    'message' => 'Telegram\'a log gönderme başarısız oldu.'
                ];
            }
        } catch (\Exception $e) {
            $this->logToFile("Telegram log file error: " . $e->getMessage(), 'ERROR');
            return [
                'status' => 500,
                'message' => 'Sunucu hatası: ' . $e->getMessage()
            ];
        }
    }

    /**
     * Upload database file to Telegram
     * Receives database backup from mobile app and uploads to Telegram
     */
    public function actionUploadDatabase()
    {
        // EN BAŞTA output buffering başlat - tüm output'u kontrol et
        ob_start();

        // Timeout'ları artır (18MB database + Telegram upload için)
        set_time_limit(300); // 5 dakika
        ini_set('max_execution_time', '300');

        $this->logToFile("=== Upload Database Action Called - CODE VERSION 7 ===", 'INFO');
        $this->logToFile("PHP Memory Limit: " . ini_get('memory_limit'), 'INFO');
        $this->logToFile("PHP Max Execution Time: " . ini_get('max_execution_time'), 'INFO');
        $this->logToFile("PHP Version: " . PHP_VERSION, 'INFO');

        try {
            // Request bilgilerini logla
            $this->logToFile("REQUEST METHOD: " . $_SERVER['REQUEST_METHOD'], 'INFO');
            $this->logToFile("Content-Type: " . ($_SERVER['CONTENT_TYPE'] ?? 'not set'), 'INFO');

            // Raw input'u direkt oku (sendLogFile gibi)
            $this->logToFile("About to read php://input...", 'INFO');
            $rawInput = file_get_contents('php://input');
            $this->logToFile("Raw input size: " . strlen($rawInput) . " bytes", 'INFO');
            $this->logToFile("Memory usage after input: " . round(memory_get_usage() / 1024 / 1024, 2) . " MB", 'INFO');

            // JSON olarak parse et
            $data = json_decode($rawInput, true);

            if (!$data) {
                $this->logToFile("Failed to parse JSON from raw input", 'ERROR');
                return $this->asJson([
                    'success' => false,
                    'message' => 'Invalid JSON data'
                ]);
            }

            $this->logToFile("JSON parsed successfully. Keys: " . implode(', ', array_keys($data)), 'INFO');

            // Base64'ten decode et
            $dbContent = base64_decode($data['database_file'] ?? '');
            $originalFileName = $data['filename'] ?? 'database.db';
            $employeeName = $data['employee_name'] ?? 'Unknown Employee';
            $warehouseCode = $data['warehouse_code'] ?? 'Unknown Warehouse';
            $fileSize = strlen($dbContent);

            $this->logToFile("After decode - fileSize: $fileSize, filename: $originalFileName", 'INFO');

            if (empty($dbContent)) {
                throw new \Exception('Database file content is empty');
            }

            $this->logToFile("Database upload request - Employee: $employeeName, Warehouse: $warehouseCode, File: $originalFileName, Size: " . number_format($fileSize / 1024 / 1024, 2) . " MB", 'INFO');

            // Telegram'a gönder
            $caption = "💾 DATABASE BACKUP\n\n";
            $caption .= "👤 Employee: $employeeName\n";
            $caption .= "🏭 Warehouse: $warehouseCode\n";
            $caption .= "📦 Size: " . number_format($fileSize / 1024 / 1024, 2) . " MB\n";
            $caption .= "📅 " . date('Y-m-d H:i:s');

            $this->logToFile("Calling WMSTelegramNotification::sendDatabaseFile...", 'INFO');

            // Output buffering başlat (WMSTelegramNotification içindeki log'lar headers göndermesin)
            ob_start();

            try {
                $success = WMSTelegramNotification::sendDatabaseFile(
                    $dbContent,
                    $originalFileName,
                    $caption
                );
                $this->logToFile("Telegram upload completed, success = " . ($success ? 'true' : 'false'), 'INFO');
            } catch (\Exception $telegramEx) {
                $this->logToFile("Telegram upload exception: " . $telegramEx->getMessage(), 'ERROR');
                $success = false;
            }

            // Tüm output'u yakala ve at
            $telegramOutput = ob_get_clean();
            $this->logToFile("Output buffer cleaned, captured " . strlen($telegramOutput) . " bytes", 'INFO');

            if ($success) {
                $this->logToFile("Database successfully uploaded to Telegram: $originalFileName", 'INFO');
                $this->logToFile("ABOUT TO RETURN SUCCESS - CODE VERSION 7", 'INFO');

                // Tüm buffer'ları temizle (hatalı output'ları at)
                while (ob_get_level() > 1) { // En dıştaki buffer'ı bırak
                    ob_end_clean();
                }

                // En dıştaki buffer'ı temizle ama bitirme
                ob_clean();

                // Şimdi headers gönder (buffer temiz olduğu için çalışmalı)
                if (!headers_sent()) {
                    header('Content-Type: application/json; charset=UTF-8');
                    http_response_code(200);
                } else {
                    $this->logToFile("WARNING: Headers already sent, cannot set Content-Type", 'WARN');
                }

                // JSON response gönder
                echo json_encode([
                    'success' => true,
                    'message' => 'Database backup successfully uploaded to Telegram'
                ], JSON_UNESCAPED_UNICODE);

                $this->logToFile("Response echoed - CODE VERSION 7", 'INFO');

                // Buffer'ı flush et ve kapat
                ob_end_flush();
                exit(0);
            } else {
                $this->logToFile("Failed to upload database to Telegram: $originalFileName", 'ERROR');
                $this->logToFile("ABOUT TO RETURN FAILURE - CODE VERSION 2", 'ERROR');

                \Yii::$app->response->statusCode = 500;
                return $this->asJson([
                    'success' => false,
                    'message' => 'Failed to upload database to Telegram'
                ]);
            }

        } catch (\Exception $e) {
            $this->logToFile("Database upload error: " . $e->getMessage(), 'ERROR');
            $this->logToFile("Stack trace: " . $e->getTraceAsString(), 'ERROR');
            $this->logToFile("ABOUT TO RETURN EXCEPTION - CODE VERSION 2", 'ERROR');

            \Yii::$app->response->statusCode = 500;
            return $this->asJson([
                'success' => false,
                'message' => 'Server error: ' . $e->getMessage()
            ]);
        }
    }

    /**
     * Warehouse count validation
     */
    private function validateWarehouseCountData($data)
    {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];

        if (empty($header) || empty($items)) {
            $errorMsg = 'Geçersiz sayım verisi: Header veya items eksik.';
            $this->logToFile("Warehouse count validation failed: $errorMsg", 'WARNING');
            return $errorMsg;
        }

        if (!isset($header['operation_unique_id'], $header['sheet_number'],
                   $header['employee_id'], $header['warehouse_code'])) {
            $errorMsg = 'Geçersiz sayım header verisi.';
            $this->logToFile("Warehouse count validation failed: $errorMsg - Missing fields in header", 'WARNING');
            return $errorMsg;
        }

        return null; // Valid
    }

    /**
     * Create or update warehouse count
     */
    private function _createWarehouseCount($data, $db)
    {
        $validationError = $this->validateWarehouseCountData($data);
        if ($validationError) {
            return ['status' => 'error', 'message' => $validationError];
        }

        $header = $data['header'];
        $items = $data['items'] ?? [];
        $operationUniqueId = $header['operation_unique_id'];

        // ℹ️ NOT: Bu fonksiyon zaten bir transaction içinden çağrılıyor (_actionSyncUpload'daki $operationTransaction)
        // Bu yüzden burada ayrı transaction başlatmıyoruz (nested transaction sorunlarını önlemek için)

        try {
            // Aynı operation_unique_id var mı kontrol et
            $existingSheet = $db->createCommand(
                'SELECT * FROM wms_count_sheets WHERE operation_unique_id = :operation_unique_id'
            )->bindValue(':operation_unique_id', $operationUniqueId)->queryOne();

            if ($existingSheet) {
                // GÜNCELLEME (SAVE & CONTINUE durumu)
                $db->createCommand()->update('wms_count_sheets', [
                    'status' => $header['status'] ?? 'in_progress',
                    'notes' => $header['notes'] ?? null,
                    'complete_date' => isset($header['complete_date']) ? $this->convertIso8601ToMysqlDatetime($header['complete_date']) : null,
                    'updated_at' => new \yii\db\Expression('NOW()'),
                ], ['operation_unique_id' => $operationUniqueId])->execute();

                $sheetId = $existingSheet['id'];

                // Mevcut items'ları sil ve yeniden ekle (full replace) - UUID ile
                $db->createCommand()->delete('wms_count_items', ['operation_unique_id' => $operationUniqueId])->execute();

                $this->logToFile("Warehouse count updated: $operationUniqueId (sheet_id: $sheetId)", 'INFO');

            } else {
                // YENİ KAYIT
                $this->logToFile("Header data: " . json_encode($header), 'DEBUG');

                // 🧹 ORPHAN TEMİZLEME: Sheet yok ama item'lar varsa, önce sil
                $orphanCount = $db->createCommand(
                    'SELECT COUNT(*) FROM wms_count_items WHERE operation_unique_id = :operation_unique_id'
                )->bindValue(':operation_unique_id', $operationUniqueId)->queryScalar();

                if ($orphanCount > 0) {
                    $this->logToFile("🧹 ORPHAN CLEANUP: Found $orphanCount orphan items for $operationUniqueId, deleting...", 'WARNING');
                    $db->createCommand()->delete('wms_count_items',
                        ['operation_unique_id' => $operationUniqueId]
                    )->execute();
                    $this->logToFile("🧹 ORPHAN CLEANUP: Deleted $orphanCount orphan items", 'WARNING');
                }

                $db->createCommand()->insert('wms_count_sheets', [
                    'operation_unique_id' => $operationUniqueId,
                    'sheet_number' => $header['sheet_number'],
                    'employee_id' => $header['employee_id'],
                    'warehouse_code' => $header['warehouse_code'],
                    'status' => $header['status'] ?? 'in_progress',
                    'notes' => $header['notes'] ?? null,
                    'start_date' => $this->convertIso8601ToMysqlDatetime($header['start_date']),
                    'complete_date' => isset($header['complete_date']) ? $this->convertIso8601ToMysqlDatetime($header['complete_date']) : null,
                    'created_at' => isset($header['created_at']) ? $this->convertIso8601ToMysqlDatetime($header['created_at']) : new \yii\db\Expression('NOW()'),
                    'updated_at' => isset($header['updated_at']) ? $this->convertIso8601ToMysqlDatetime($header['updated_at']) : new \yii\db\Expression('NOW()'),
                ])->execute();

                $sheetId = $db->getLastInsertID();

                $this->logToFile("New warehouse count created: $operationUniqueId (sheet_id: $sheetId)", 'INFO');
            }

            // Items ekle
            $itemCount = count($items);
            $this->logToFile("Warehouse count: Adding $itemCount items for operation $operationUniqueId", 'INFO');

            $successCount = 0;
            $errorCount = 0;
            $skippedCount = 0;
            $seenUuids = []; // Duplicate UUID detection

            foreach ($items as $index => $item) {
                try {
                    $itemUuid = $item['item_uuid'] ?? 'NO_UUID';
                    $stokKodu = $item['StokKodu'] ?? 'NO_STOK_KODU';
                    $quantity = $item['quantity_counted'] ?? 0;

                    $this->logToFile("Warehouse count item #$index: UUID=$itemUuid, StokKodu=$stokKodu, Qty=$quantity", 'DEBUG');

                    // ✅ DUPLICATE UUID KONTROLÜ (Aynı request içinde)
                    if (isset($seenUuids[$itemUuid])) {
                        $skippedCount++;
                        $this->logToFile("⚠️ DUPLICATE UUID in same request: $itemUuid (item #$index) - SKIPPED", 'WARNING');
                        continue; // Bu item'ı atla, hataya düşme
                    }
                    $seenUuids[$itemUuid] = true;

                    $db->createCommand()->insert('wms_count_items', [
                        'operation_unique_id' => $operationUniqueId,
                        'item_uuid' => $item['item_uuid'],
                        'birim_key' => $item['birim_key'] ?? null,
                        'pallet_barcode' => $item['pallet_barcode'] ?? null,
                        'quantity_counted' => $item['quantity_counted'],
                        'barcode' => $item['barcode'] ?? null,
                        'StokKodu' => $item['StokKodu'] ?? null,
                        'shelf_code' => $item['shelf_code'] ?? null,
                        'expiry_date' => $item['expiry_date'] ?? null,
                        'is_damaged' => isset($item['is_damaged']) ? ($item['is_damaged'] ? 1 : 0) : 0,
                        'created_at' => isset($item['created_at']) ? $this->convertIso8601ToMysqlDatetime($item['created_at']) : new \yii\db\Expression('NOW()'),
                        'updated_at' => isset($item['updated_at']) ? $this->convertIso8601ToMysqlDatetime($item['updated_at']) : new \yii\db\Expression('NOW()'),
                    ])->execute();

                    $successCount++;
                } catch (\Exception $itemError) {
                    $errorCount++;
                    $errorMsg = "Warehouse count item insertion failed at index $index: " . $itemError->getMessage();
                    $this->logToFile($errorMsg . " | Item data: " . json_encode($item), 'ERROR');
                    throw new \Exception($errorMsg); // Re-throw to trigger main catch block
                }
            }

            $this->logToFile("Warehouse count items completed: $successCount success, $errorCount errors", 'INFO');

            // ✅ Başarılı - Outer transaction (actionSyncUpload) commit edecek
            $this->logToFile("✅ Warehouse count operation completed successfully for $operationUniqueId", 'INFO');

            return [
                'status' => 'success',
                'count_sheet_id' => $sheetId,
                'message' => 'Sayım başarıyla kaydedildi'
            ];

        } catch (\Exception $e) {
            // 🔄 Exception throw ediliyor - Outer transaction (actionSyncUpload) rollback edecek
            $errorMsg = $e->getMessage();
            $this->logToFile("🔄 Transaction rolled back due to error: " . $errorMsg, 'ERROR');
            $this->logToFile("Warehouse count error trace: " . $e->getTraceAsString(), 'ERROR');

            // Telegram'a detaylı hata log dosyası gönder
            try {
                $employeeData = $db->createCommand(
                    'SELECT first_name, last_name FROM employees WHERE id = :id'
                )->bindValue(':id', $header['employee_id'] ?? 0)->queryOne();

                $employeeName = $employeeData
                    ? trim($employeeData['first_name'] . ' ' . $employeeData['last_name'])
                    : 'Bilinmeyen';

                // Detaylı log içeriği oluştur
                $logContent = "=== WAREHOUSE COUNT ERROR ===\n\n";
                $logContent .= "Timestamp: " . date('Y-m-d H:i:s') . "\n";
                $logContent .= "Employee: {$employeeName}\n";
                $logContent .= "Employee ID: " . ($header['employee_id'] ?? 'N/A') . "\n";
                $logContent .= "Sheet Number: " . ($header['sheet_number'] ?? 'N/A') . "\n";
                $logContent .= "Warehouse Code: " . ($header['warehouse_code'] ?? 'N/A') . "\n";
                $logContent .= "Operation ID: " . ($operationUniqueId ?? 'N/A') . "\n";
                $logContent .= "Items Count: " . count($items) . "\n\n";

                $logContent .= "=== ERROR DETAILS ===\n";
                $logContent .= "Error Message: {$errorMsg}\n\n";

                $logContent .= "=== STACK TRACE ===\n";
                $logContent .= $e->getTraceAsString() . "\n\n";

                $logContent .= "=== HEADER DATA ===\n";
                $logContent .= json_encode($header, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n\n";

                if (!empty($items)) {
                    $logContent .= "=== ITEMS DATA (First 5) ===\n";
                    $itemsToLog = array_slice($items, 0, 5);
                    $logContent .= json_encode($itemsToLog, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n\n";

                    if (count($items) > 5) {
                        $logContent .= "... and " . (count($items) - 5) . " more items\n\n";
                    }
                }

                $logContent .= "=== SERVER INFO ===\n";
                $logContent .= "Server: " . (gethostname() ?: 'Unknown') . "\n";
                $logContent .= "PHP Version: " . PHP_VERSION . "\n";
                $logContent .= "Database: vtrowhub\n";

                // TXT dosyası olarak gönder
                WMSTelegramNotification::sendLogFile(
                    '📊 DEPO SAYIM HATASI',
                    $logContent,
                    [
                        'Server' => gethostname() ?: 'Unknown',
                        'Database' => 'vtrowhub'
                    ],
                    $employeeName
                );
            } catch (\Exception $telegramError) {
                $this->logToFile("Telegram log file notification failed: " . $telegramError->getMessage(), 'WARNING');
            }

            return ['status' => 'error', 'message' => 'Veritabanı hatası: ' . $errorMsg];
        }
    }
}
