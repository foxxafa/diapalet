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

        if ($action->id !== 'login' && $action->id !== 'health-check' && $action->id !== 'sync-shelfs') {
            $this->checkApiKey();
        }

        return parent::beforeAction($action);
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
        foreach ($data as &$row) {
            foreach ($intKeys as $key) {
                if (isset($row[$key])) $row[$key] = (int)$row[$key];
            }
            foreach ($floatKeys as $key) {
                if (isset($row[$key])) $row[$key] = (float)$row[$key];
            }
        }
    }

    public function actionLogin()
    {
        $params = $this->getJsonBody();
        $username = $params['username'] ?? null;
        $password = $params['password'] ?? null;

        if (!$username || !$password) {
            Yii::$app->response->statusCode = 400;
            return $this->asJson(['status' => 400, 'message' => 'Kullanıcı adı ve şifre gereklidir.']);
        }

        try {
            // Rowhub formatında giriş sorgusu
            $userQuery = (new Query())
                ->select([
                    'e.id', 'e.first_name', 'e.last_name', 'e.username',
                    'e.warehouse_code',
                    'COALESCE(w.name, "Default Warehouse") as warehouse_name',
                    'COALESCE(w.id, 1) as warehouse_id',
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
                $apiKey = Yii::$app->security->generateRandomString();
                $userData = [
                    'id' => (int)$user['id'],
                    'first_name' => $user['first_name'],
                    'last_name' => $user['last_name'],
                    'username' => $user['username'],
                    'warehouse_id' => (int)($user['warehouse_id'] ?? 1),
                    'warehouse_name' => $user['warehouse_name'],
                    'warehouse_code' => $user['warehouse_code'],
                    'receiving_mode' => (int)($user['receiving_mode'] ?? 2),
                    'branch_id' => (int)($user['branch_id'] ?? 1),
                    'branch_name' => $user['branch_name'],
                ];
                return $this->asJson([
                    'status' => 200, 'message' => 'Giriş başarılı.',
                    'user' => $userData, 'apikey' => $apiKey
                ]);
            } else {
                Yii::$app->response->statusCode = 401;
                return $this->asJson(['status' => 401, 'message' => 'Kullanıcı adı veya şifre hatalı.']);
            }
        } catch (\yii\db\Exception $e) {
            Yii::error("Login DB Hatası: " . $e->getMessage(), __METHOD__);
            Yii::$app->response->statusCode = 500;
            return $this->asJson(['status' => 500, 'message' => 'Sunucu tarafında bir hata oluştu: ' . $e->getMessage()]);
        } catch (\Exception $e) {
            Yii::error("Login Genel Hatası: " . $e->getMessage(), __METHOD__);
            Yii::$app->response->statusCode = 500;
            return $this->asJson(['status' => 500, 'message' => 'Beklenmeyen hata: ' . $e->getMessage()]);
        }
    }

    public function actionSyncUpload()
    {
        $payload = $this->getJsonBody();
        $operations = $payload['operations'] ?? [];
        $db = Yii::$app->db;
        $results = [];

        if (empty($operations)) {
            return ['success' => true, 'results' => []];
        }


        $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);

        try {
            // Transaction timeout ayarla (MySQL için)
            $db->createCommand("SET SESSION innodb_lock_wait_timeout = 10")->execute();

            foreach ($operations as $op) {
                $localId = $op['local_id'] ?? null;
                $idempotencyKey = $op['idempotency_key'] ?? null;

                if (!$localId || !$idempotencyKey) {
                    throw new \Exception("Tüm operasyonlar 'local_id' ve 'idempotency_key' içermelidir.");
                }

                // 1. IDEMPOTENCY KONTROLÜ
                $existingRequest = (new Query())
                    ->from('processed_requests')
                    ->where(['idempotency_key' => $idempotencyKey])
                    ->one($db);

                if ($existingRequest) {
                    // 2. Bu işlem daha önce yapılmışsa, kayıtlı sonucu döndür.
                    $resultData = json_decode($existingRequest['response_body'], true);
                    $results[] = [
                        'local_id' => (int)$localId,
                        'result' => is_string($resultData) ? json_decode($resultData, true) : $resultData
                    ];
                    continue; // Sonraki operasyona geç
                }

                // 3. Yeni işlem ise, operasyonu işle.
                $opType = $op['type'] ?? 'unknown';
                $opData = $op['data'] ?? [];
                $result = ['status' => 'error', 'message' => "Bilinmeyen operasyon tipi: {$opType}"];


                if ($opType === 'goodsReceipt') {
                    $result = $this->_createGoodsReceipt($opData, $db);
                } elseif ($opType === 'inventoryTransfer') {
                    $result = $this->_createInventoryTransfer($opData, $db);
                } elseif ($opType === 'forceCloseOrder') {
                    $result = $this->_forceCloseOrder($opData, $db);
                }

                // 4. Başarılı ise, sonucu hem yanıt dizisine hem de idempotency tablosuna ekle
                if (isset($result['status']) && $result['status'] === 'success') {
                    $db->createCommand()->insert('processed_requests', [
                        'idempotency_key' => $idempotencyKey,
                        'response_code' => 200,
                        'response_body' => json_encode($result)
                    ])->execute();

                    $results[] = ['local_id' => (int)$localId, 'result' => $result];
                } else {
                    // İşlem başarısız olsa bile idempotency anahtarı ile hatayı kaydet.
                    // Bu, aynı hatalı isteğin tekrar tekrar işlenmesini önler.
                    $db->createCommand()->insert('processed_requests', [
                        'idempotency_key' => $idempotencyKey,
                        'response_code' => 500, // veya uygun bir hata kodu
                        'response_body' => json_encode($result)
                    ])->execute();

                    $errorMsg = "İşlem (ID: {$localId}, Tip: {$opType}) başarısız: " . ($result['message'] ?? 'Bilinmeyen hata');
                    Yii::error($errorMsg, __METHOD__);
                    throw new \Exception($errorMsg);
                }
            }

            $transaction->commit();
            return ['success' => true, 'results' => $results];

        } catch (\Exception $e) {
            $transaction->rollBack();
            $errorDetail = "SyncUpload Toplu İşlem Hatası: {$e->getMessage()}\nTrace: {$e->getTraceAsString()}";
            Yii::error($errorDetail, __METHOD__);
            Yii::$app->response->setStatusCode(500);
            return [
                'success' => false,
                'error' => 'İşlem sırasında bir hata oluştu ve geri alındı.',
                'details' => $e->getMessage(),
                'processed_count' => count($results)
            ];
        }
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
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || empty($header['employee_id'])) {
            return ['status' => 'error', 'message' => 'Geçersiz mal kabul verisi.'];
        }

        $siparisId = $header['siparis_id'] ?? null;
        $deliveryNoteNumber = $header['delivery_note_number'] ?? null;

        // Serbest mal kabulde fiş numarası zorunludur.
        if ($siparisId === null && empty($deliveryNoteNumber)) {
            return ['status' => 'error', 'message' => 'Serbest mal kabul için irsaliye numarası (delivery_note_number) zorunludur.'];
        }

        // Çalışanın depo ID'sini al - Rowhub formatında
        $employeeId = $header['employee_id'];
        
        // DEBUG: Employee warehouse mapping'i kontrol et
        $employeeInfo = (new Query())
            ->select(['e.id', 'e.warehouse_code', 'w.id as warehouse_id', 'w.warehouse_code as w_warehouse_code'])
            ->from(['e' => 'employees'])
            ->leftJoin(['w' => 'warehouses'], 'e.warehouse_code = w.warehouse_code')
            ->where(['e.id' => $employeeId])
            ->one($db);
            
        Yii::info("DEBUG createGoodsReceipt - employee_id: $employeeId", __METHOD__);
        Yii::info("DEBUG employee info: " . json_encode($employeeInfo), __METHOD__);
        
        $warehouseId = $employeeInfo['warehouse_id'] ?? null;

        if (!$warehouseId) {
            return ['status' => 'error', 'message' => 'Çalışanın warehouse bilgisi bulunamadı. Employee warehouse_code: ' . ($employeeInfo['warehouse_code'] ?? 'null')];
        }

        $db->createCommand()->insert('goods_receipts', [
            'receipt_date' => $header['receipt_date'] ?? new \yii\db\Expression('NOW()'),
            'warehouse_id' => $warehouseId,
            'employee_id' => $header['employee_id'],
            'siparis_id' => $siparisId,
            'delivery_note_number' => $deliveryNoteNumber,
        ])->execute();
        $receiptId = $db->getLastInsertID();

        foreach ($items as $item) {
            // Mobile'dan urun_key (_key değeri) geliyor, direkt yazılıyor
            $urunKey = $item['urun_key']; // _key değeri
            
            // _key'in gerçekten var olduğunu kontrol et
            $exists = (new Query())
                ->from('urunler')
                ->where(['_key' => $urunKey])
                ->exists($db);
            
            if (!$exists) {
                return ['status' => 'error', 'message' => 'Ürün bulunamadı: ' . $urunKey];
            }
            
            // Sipariş bazlı mal kabulde siparis_key'i bul
            $siparisKey = null;
            if ($siparisId) {
                // Ürünün StokKodu'nu al
                $stokKodu = (new Query())
                    ->select('StokKodu')
                    ->from('urunler')
                    ->where(['_key' => $urunKey])
                    ->scalar($db);
                
                if ($stokKodu) {
                    // siparis_ayrintili tablosundan _key değerini bul
                    // siparis_ayrintili'de stok_kodu değil kartkodu var
                    $siparisKey = (new Query())
                        ->select('_key')
                        ->from('siparis_ayrintili')
                        ->where(['siparisler_id' => $siparisId, 'kartkodu' => $stokKodu])
                        ->scalar($db);
                }
            }
            
            $db->createCommand()->insert('goods_receipt_items', [
                'receipt_id' => $receiptId, 'urun_key' => $urunKey, // _key değeri direkt yazılıyor
                'quantity_received' => $item['quantity'], 'pallet_barcode' => $item['pallet_barcode'] ?? null,
                'expiry_date' => $item['expiry_date'] ?? null,
                'siparis_key' => $siparisKey,
            ])->execute();

            // DÜZELTME: Stok, fiziksel bir 'Mal Kabul' rafına değil, location_id'si NULL olan
            // sanal bir alana eklenir.
            $stockStatus = 'receiving'; // Tüm mal kabulleri için, stok başlangıçta 'mal kabul' durumunda olmalıdır.
            // _key değeri direkt kullanılıyor
            $this->upsertStock($db, $urunKey, null, $item['quantity'], $item['pallet_barcode'] ?? null, $stockStatus, $siparisId, $item['expiry_date'] ?? null, $receiptId);
        }

        // DIA entegrasyonu - Mal kabul işlemi DIA'ya gönderilir
         try {
            $goodsReceipt = GoodsReceipts::findOne($receiptId);
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
            Yii::error("DIA entegrasyonu hatası (Receipt ID: $receiptId): " . $e->getMessage(), __METHOD__);
        }

        if ($siparisId) {
            $this->checkAndFinalizeReceiptStatus($db, $siparisId);
        }

        return ['status' => 'success', 'receipt_id' => $receiptId];
    }

    private function _createInventoryTransfer($data, $db) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || !isset($header['employee_id'], $header['target_location_id']) || !array_key_exists('source_location_id', $header)) {
            return ['status' => 'error', 'message' => 'Geçersiz transfer verisi.'];
        }

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
            
            // _key'in gerçekten var olduğunu kontrol et
            $exists = (new Query())
                ->from('urunler')
                ->where(['_key' => $urunKey])
                ->exists($db);
            
            if (!$exists) {
                return ['status' => 'error', 'message' => 'Ürün bulunamadı: ' . $urunKey];
            }
            
            $totalQuantityToTransfer = (float)$item['quantity'];
            $sourcePallet = $item['pallet_id'] ?? null;
            $targetPallet = ($operationType === 'pallet_transfer') ? $sourcePallet : null;

            // 1. İlk giren ilk çıkar mantığı ile kaynak stokları bul
            $sourceStocksQuery = new Query();
            $sourceStocksQuery->from('inventory_stock')
                ->where(['urun_key' => $urunKey, 'stock_status' => $sourceStatus]);
            $this->addNullSafeWhere($sourceStocksQuery, 'location_id', $sourceLocationId);
            $this->addNullSafeWhere($sourceStocksQuery, 'pallet_barcode', $sourcePallet);

            // Rafa yerleştirme işlemleri için, belirli sipariş veya fişe göre filtrelememiz gerekir
            if ($isPutawayOperation) {
                if ($siparisId) {
                    $this->addNullSafeWhere($sourceStocksQuery, 'siparis_id', $siparisId);
                } elseif ($deliveryNoteNumber) {
                    // Serbest mal kabul için irsaliye numarası üzerinden fiş ID'sini bul
                    $actualGoodsReceiptId = (new Query())
                        ->select('goods_receipt_id')
                        ->from('goods_receipts')
                        ->where(['delivery_note_number' => $deliveryNoteNumber])
                        ->scalar($db);
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
                return ['status' => 'error', 'message' => "Yetersiz stok. Ürün ID: {$urunKey}, Mevcut: {$totalAvailable}, İstenen: {$totalQuantityToTransfer}. Context: {$errorContext}"];
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
                    $targetLocationId,
                    $portion['qty'],
                    $targetPallet,
                    'available',
                    // GÜNCELLEME: Null yerine kaynak stoktaki ID'leri gönderiyoruz
                    $portion['siparis_id'],
                    $portion['expiry'],
                    $portion['goods_receipt_id']
                );

                // 5. Her kısım için ayrı transfer kaydı oluştur
                // _key urun_key olarak kullanılıyor
                $transferData = [
                    'urun_key'            => $urunKey, // _key yazılıyor
                    'from_location_id'    => $sourceLocationId,
                    'to_location_id'      => $targetLocationId,
                    'quantity'            => $portion['qty'],
                    'from_pallet_barcode' => $sourcePallet,
                    'pallet_barcode'      => $targetPallet,
                    'goods_receipt_id'    => $goodsReceiptId,
                    'delivery_note_number' => $deliveryNoteNumber,
                    'employee_id'         => $header['employee_id'],
                    'transfer_date'       => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
                ];

                if ($siparisId) {
                    $transferData['siparis_id'] = $siparisId;
                }

                $db->createCommand()->insert('inventory_transfers', $transferData)->execute();
            }

            // 6. Sipariş bazlı işlemler için rafa yerleştirme durumunu güncelle
            if ($isPutawayOperation && $siparisId) {
                 // _key ile ürün bulup sipariş satırını bul
                 $productCode = (new Query())->select('StokKodu')->from('urunler')->where(['_key' => $urunKey])->scalar($db);
                 if ($productCode) {
                     $orderLine = (new Query())->from('siparis_ayrintili')->where(['siparisler_id' => $siparisId, 'kartkodu' => $productCode, 'turu' => '1'])->one($db);
                     if ($orderLine) {
                         $orderLineId = $orderLine['id'];
                         $sql = "INSERT INTO wms_putaway_status (purchase_order_line_id, putaway_quantity) VALUES (:line_id, :qty) ON DUPLICATE KEY UPDATE putaway_quantity = putaway_quantity + VALUES(putaway_quantity)";
                         $db->createCommand($sql, [':line_id' => $orderLineId, ':qty' => $totalQuantityToTransfer])->execute();
                     }
                 }
            }
        }

        if ($isPutawayOperation && $siparisId) {
            $this->checkAndFinalizePoStatus($db, $siparisId);
        }

        return ['status' => 'success'];
    }

    private function upsertStock($db, $urunKey, $locationId, $qtyChange, $palletBarcode, $stockStatus, $siparisId = null, $expiryDate = null, $goodsReceiptId = null) {
        $isDecrement = (float)$qtyChange < 0;

        if ($isDecrement) {
            // Bu fonksiyon artık _createInventoryTransfer'da kullanılmıyor,
            // ama diğer yerlerde kullanılma ihtimaline karşı bırakıldı.
            // Mantığı önceki adımdaki gibi (while döngüsü) kalabilir.
            $toDecrement = abs((float)$qtyChange);

            $availabilityQuery = new Query();
            $availabilityQuery->from('inventory_stock')->where(['urun_key' => $urunKey, 'stock_status' => $stockStatus]);
            $this->addNullSafeWhere($availabilityQuery, 'location_id', $locationId);
            $this->addNullSafeWhere($availabilityQuery, 'pallet_barcode', $palletBarcode);
            $this->addNullSafeWhere($availabilityQuery, 'siparis_id', $siparisId);
            $this->addNullSafeWhere($availabilityQuery, 'goods_receipt_id', $goodsReceiptId);
            $totalAvailable = (float)$availabilityQuery->sum('quantity', $db);

            if ($totalAvailable < $toDecrement - 0.001) {
                 throw new \Exception("Stok düşürme hatası: Kaynakta yeterli stok yok. Mevcut: {$totalAvailable}, İstenen: {$toDecrement}");
            }

            while ($toDecrement > 0.001) {
                $query = new Query();
                $query->from('inventory_stock')->where(['urun_key' => $urunKey, 'stock_status' => $stockStatus]);
                $this->addNullSafeWhere($query, 'location_id', $locationId);
                $this->addNullSafeWhere($query, 'pallet_barcode', $palletBarcode);
                $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
                $this->addNullSafeWhere($query, 'goods_receipt_id', $goodsReceiptId);
                $query->orderBy(['expiry_date' => SORT_ASC])->limit(1);

                $stock = $query->one($db);

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
                    $db->createCommand()->delete('inventory_stock', ['id' => $stockId])->execute();
                    $toDecrement -= $currentQty;
                }
            }
        } else {
            // --- Stok Ekleme Mantığı ---
            $query = new Query();
            $query->from('inventory_stock')
                  ->where(['urun_key' => $urunKey, 'stock_status' => $stockStatus]);

            $this->addNullSafeWhere($query, 'location_id', $locationId);
            $this->addNullSafeWhere($query, 'pallet_barcode', $palletBarcode);
            $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
            $this->addNullSafeWhere($query, 'expiry_date', $expiryDate);
            $this->addNullSafeWhere($query, 'goods_receipt_id', $goodsReceiptId);

            $stock = $query->one($db);

            if ($stock) {
                $newQty = (float)($stock['quantity']) + (float)$qtyChange;
                if ($newQty > 0.001) {
                    $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $stock['id']])->execute();
                } else {
                    $db->createCommand()->delete('inventory_stock', ['id' => $stock['id']])->execute();
                }
            } elseif ($qtyChange > 0) {
                // _key urun_key olarak kullanılıyor
                $db->createCommand()->insert('inventory_stock', [
                    'urun_key' => $urunKey, 'location_id' => $locationId, 'siparis_id' => $siparisId,
                    'quantity' => (float)$qtyChange, 'pallet_barcode' => $palletBarcode,
                    'stock_status' => $stockStatus, 'expiry_date' => $expiryDate,
                    'goods_receipt_id' => $goodsReceiptId,
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
                s.anamiktar,
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

        $allLinesCompleted = true;
        $anyLineReceived = false;

        foreach ($lines as $line) {
            $ordered = (float)$line['anamiktar'];
            $received = (float)$line['received_quantity'];

            if ($received > 0.001) {
                $anyLineReceived = true;
            }
            if ($received < $ordered - 0.001) {
                $allLinesCompleted = false;
            }
        }

        $newStatus = null;
        if ($allLinesCompleted && $anyLineReceived) {
            $newStatus = 3; // Tamamen kabul edildi (sipariş edilen = kabul edilen)
        } elseif ($anyLineReceived) {
            $newStatus = 1; // Kısmi kabul (sipariş edilen > kabul edilen)
        }

        if ($newStatus !== null) {
            $currentStatus = (new Query())->select('status')->from('siparisler')->where(['id' => $siparisId])->scalar($db);
            if ($currentStatus != $newStatus) {
                $db->createCommand()->update('siparisler', ['status' => $newStatus], ['id' => $siparisId])->execute();
            }
        }
    }

    private function checkAndFinalizePoStatus($db, $siparisId) {
        if (!$siparisId) return;

        // Sipariş satırlarını ve yerleştirilmiş miktarları wms_putaway_status'tan al
        $orderLines = (new Query())
            ->select(['s.id', 's.anamiktar', 'w.putaway_quantity'])
            ->from(['s' => 'siparis_ayrintili'])
            ->leftJoin(['w' => 'wms_putaway_status'], 's.id = w.purchase_order_line_id')
            ->where(['s.siparisler_id' => $siparisId, 's.turu' => '1'])
            ->all($db);

        if (empty($orderLines)) return;

        $allLinesCompleted = true;
        foreach ($orderLines as $line) {
            $ordered = (float)$line['anamiktar'];
            $putaway = (float)($line['putaway_quantity'] ?? 0);
            if ($putaway < $ordered - 0.001) { // Kayan nokta hataları için tolerans
                $allLinesCompleted = false;
                break;
            }
        }

        // Rafa yerleştirme artık sipariş statusunu değiştirmiyor
        // Status sadece mal kabul aşamasında belirleniyor (0,1,2,3)
        // Bu metod sadece putaway takibi için kullanılıyor
    }

    private function _forceCloseOrder($data, $db) {
        $siparisId = $data['siparis_id'] ?? null;
        if (empty($siparisId)) {
            return ['status' => 'error', 'message' => 'Geçersiz veri: "siparis_id" eksik.'];
        }
        // Statü: 2 (Manuel Kapatıldı)
        $count = $db->createCommand()->update('siparisler', ['status' => 2], ['id' => $siparisId])->execute();

        if ($count > 0) {
            return ['status' => 'success', 'message' => "Order #$siparisId closed."];
        } else {
            return ['status' => 'not_found', 'message' => "Order #$siparisId not found."];
        }
    }

    public function actionSyncCounts()
    {
        $payload = $this->getJsonBody();
        $warehouseId = $payload['warehouse_id'] ?? null;
        $lastSyncTimestamp = $payload['last_sync_timestamp'] ?? null;

        if (!$warehouseId) {
            Yii::$app->response->statusCode = 400;
            return ['success' => false, 'error' => 'Depo ID (warehouse_id) zorunludur.'];
        }
        $warehouseId = (int)$warehouseId;

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
            $counts['wms_putaway_status'] = $this->getPutawayStatusCount($warehouseKey, $serverSyncTimestamp);

            return [
                'success' => true,
                'counts' => $counts,
                'total_records' => array_sum($counts),
                'timestamp' => (new \DateTime('now', new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.u\Z')
            ];

        } catch (\Exception $e) {
            Yii::$app->response->statusCode = 500;
            Yii::error("SyncCounts Hatası: " . $e->getMessage(), __METHOD__);
            return ['success' => false, 'error' => 'Count sorgusu başarısız: ' . $e->getMessage()];
        }
    }

    private function getTableCount($tableName, $timestamp = null, $extraConditions = []) 
    {
        $query = (new Query())->from($tableName);
        
        if ($timestamp) {
            $query->where(['>', 'updated_at', $timestamp]);
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
            ->andWhere(['in', 'status', [0, 1, 2, 3]]);
            
        if ($timestamp) {
            $query->andWhere(['>', 'updated_at', $timestamp]);
        }
        
        return (int)$query->count();
    }

    private function getOrderLinesCount($warehouseKey, $timestamp = null) 
    {
        $query = (new Query())
            ->from('siparis_ayrintili')
            ->where(['siparis_ayrintili.turu' => '1']); // FIX: Table prefix added
            
        if ($timestamp) {
            $query->andWhere(['>', 'siparis_ayrintili.updated_at', $timestamp]); // DÜZELTME: Tablo öneki eklendi
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
        $query = (new Query())->from('goods_receipts')->where(['warehouse_id' => $warehouseId]);
        if ($timestamp) {
            $query->andWhere(['>', 'updated_at', $timestamp]);
        }
        return (int)$query->count();
    }

    private function getGoodsReceiptItemsCount($warehouseId, $timestamp = null) 
    {
        $query = (new Query())
            ->from('goods_receipt_items')
            ->innerJoin('goods_receipts', 'goods_receipts.goods_receipt_id = goods_receipt_items.receipt_id')
            ->where(['goods_receipts.warehouse_id' => $warehouseId]);
            
        if ($timestamp) {
            $query->andWhere(['>', 'goods_receipt_items.updated_at', $timestamp]);
        }
        return (int)$query->count();
    }

    private function getInventoryStockCount($warehouseId, $timestamp = null) 
    {
        // Kompleks stok sorgusu - location bazlı ve goods_receipt bazlı
        $locationIds = (new Query())->select('id')->from('shelfs')->where(['warehouse_id' => $warehouseId])->column();
        $receiptIds = (new Query())->select('goods_receipt_id')->from('goods_receipts')->where(['warehouse_id' => $warehouseId])->column();
        
        // DEBUG: Count alma sorununu tespit et
        Yii::info("DEBUG getInventoryStockCount - warehouse_id: $warehouseId", __METHOD__);
        Yii::info("DEBUG locationIds count: " . count($locationIds), __METHOD__);
        Yii::info("DEBUG receiptIds count: " . count($receiptIds), __METHOD__);
        
        // DEBUG: Mevcut receipt 71'i kontrol et
        $receipt71 = (new Query())
            ->select(['goods_receipt_id', 'warehouse_id', 'delivery_note_number'])
            ->from('goods_receipts')
            ->where(['goods_receipt_id' => 71])
            ->one();
        Yii::info("DEBUG Receipt 71: " . json_encode($receipt71), __METHOD__);
        
        $query = (new Query())->from('inventory_stock');
        $conditions = ['or'];
        
        if (!empty($locationIds)) {
            $conditions[] = ['in', 'location_id', $locationIds];
            Yii::info("DEBUG: location_id condition added", __METHOD__);
        }
        if (!empty($receiptIds)) {
            $conditions[] = [
                'and',
                ['is', 'location_id', new \yii\db\Expression('NULL')],
                ['in', 'goods_receipt_id', $receiptIds]
            ];
            Yii::info("DEBUG: goods_receipt_id condition added", __METHOD__);
        }
        
        Yii::info("DEBUG conditions count: " . count($conditions), __METHOD__);
        
        if (count($conditions) > 1) {
            $query->where($conditions);
            if ($timestamp) {
                $query->andWhere(['>', 'updated_at', $timestamp]);
            }
            $result = (int)$query->count();
            Yii::info("DEBUG final inventory_stock count: $result", __METHOD__);
            return $result;
        }
        Yii::info("DEBUG: Returning 0 because no conditions", __METHOD__);
        return 0;
    }

    private function getInventoryTransfersCount($warehouseId, $timestamp = null) 
    {
        $locationIds = (new Query())->select('id')->from('shelfs')->where(['warehouse_id' => $warehouseId])->column();
        $receiptIds = (new Query())->select('goods_receipt_id')->from('goods_receipts')->where(['warehouse_id' => $warehouseId])->column();
        
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
                $query->andWhere(['>', 'updated_at', $timestamp]);
            }
            return (int)$query->count();
        }
        return 0;
    }

    private function getPutawayStatusCount($warehouseKey, $timestamp = null) 
    {
        $query = (new Query())
            ->from('wms_putaway_status')
            ->innerJoin('siparis_ayrintili', 'siparis_ayrintili.id = wms_putaway_status.purchase_order_line_id')
            ->innerJoin('siparisler', 'siparisler.id = siparis_ayrintili.siparisler_id')
            ->where(['siparisler._key_sis_depo_source' => $warehouseKey]);
            
        if ($timestamp) {
            $query->andWhere(['>', 'wms_putaway_status.updated_at', $timestamp]);
        }
        return (int)$query->count();
    }

    public function actionSyncDownload()
{
    $payload = $this->getJsonBody();
    $warehouseId = $payload['warehouse_id'] ?? null;
    $lastSyncTimestamp = $payload['last_sync_timestamp'] ?? null;
    
    // ########## YENİ PAGINATION PARAMETRELERİ ##########
    $tableName = $payload['table_name'] ?? null;
    $page = (int)($payload['page'] ?? 1);
    $limit = (int)($payload['limit'] ?? 5000);
    
    if (!$warehouseId) {
        Yii::$app->response->statusCode = 400;
        return ['success' => false, 'error' => 'Depo ID (warehouse_id) zorunludur.'];
    }
    $warehouseId = (int)$warehouseId;
    
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
                $urunlerQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            } else {
                // İlk sync ise tüm ürünleri al (aktif/pasif ayrımı olmadan)
                // Mobil uygulama kendi filtrelemesini yapar
            }
            
            // DÜZELTME: Tüm ürünleri gönder (aktif=0 olanlar da dahil)
            // Mobil uygulama WHERE u.aktif = 1 filtresi kullanıyor, bu nedenle 
            // server'dan aktif=0 olanlar da gelmeli ki mobil tarafta doğru çalışsın

            $urunlerData = $urunlerQuery->all();
            $this->castNumericValues($urunlerData, ['id', 'aktif']);
            $data['urunler'] = $urunlerData;

        } catch (\Exception $e) {
            Yii::error("Ürünler tablosu hatası: " . $e->getMessage(), __METHOD__);
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
                $tedarikciQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            } else {
                // İlk sync ise tüm tedarikçileri al
            }

            $tedarikciData = $tedarikciQuery->all();
            $this->castNumericValues($tedarikciData, ['id', 'Aktif']);
            $data['tedarikci'] = $tedarikciData;

        } catch (\Exception $e) {
            Yii::error("Tedarikçi tablosu hatası: " . $e->getMessage(), __METHOD__);
            throw new \Exception("Tedarikçi tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## TEDARİKÇİ İNKREMENTAL SYNC BİTTİ ##########

        // ########## BİRİMLER İÇİN İNKREMENTAL SYNC ##########
        try {
            $birimlerQuery = (new Query())
                ->select(['id', 'birimadi', 'birimkod', 'carpan', '_key', '_key_scf_stokkart', 'StokKodu', 
                         'created_at', 'updated_at'])
                ->from('birimler');

            if ($serverSyncTimestamp) {
                $birimlerQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            } else {
            }

            $birimlerData = $birimlerQuery->all();
            $this->castNumericValues($birimlerData, ['id'], ['carpan']);
            $data['birimler'] = $birimlerData;

        } catch (\Exception $e) {
            Yii::error("Birimler tablosu hatası: " . $e->getMessage(), __METHOD__);
            throw new \Exception("Birimler tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## BİRİMLER İNKREMENTAL SYNC BİTTİ ##########

        // ########## BARKODLAR İÇİN İNKREMENTAL SYNC ##########
        try {
            $barkodlarQuery = (new Query())
                ->select(['id', '_key', '_key_scf_stokkart_birimleri', 'barkod', 'turu', 'created_at', 'updated_at'])
                ->from('barkodlar');

            if ($serverSyncTimestamp) {
                $barkodlarQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            } else {
            }

            $barkodlarData = $barkodlarQuery->all();
            $this->castNumericValues($barkodlarData, ['id']);
            $data['barkodlar'] = $barkodlarData;

        } catch (\Exception $e) {
            Yii::error("Barkodlar tablosu hatası: " . $e->getMessage(), __METHOD__);
            throw new \Exception("Barkodlar tablosu sorgusu başarısız: " . $e->getMessage());
        }
        // ########## BARKODLAR İNKREMENTAL SYNC BİTTİ ##########

        // ########## SHELFS İÇİN İNKREMENTAL SYNC ##########
        $shelfsQuery = (new Query())
            ->select(['id', 'warehouse_id', 'name', 'code', 'is_active', 'created_at', 'updated_at'])
            ->from('shelfs')
            ->where(['warehouse_id' => $warehouseId]);
        if ($serverSyncTimestamp) {
            $shelfsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
        } else {
        }
        $data['shelfs'] = $shelfsQuery->all();
        $this->castNumericValues($data['shelfs'], ['id', 'warehouse_id', 'is_active']);

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
            'e.warehouse_code', 'e.is_active', 'e.created_at', 'e.updated_at'
        ];
        $employeesQuery = (new Query())
            ->select($employeeColumns)
            ->from(['e' => 'employees'])
            ->where(['e.is_active' => 1, 'e.warehouse_code' => $warehouseCode]);

        if ($serverSyncTimestamp) {
            $employeesQuery->andWhere(['>', 'e.updated_at', $serverSyncTimestamp]);
        } else {
        }
        $data['employees'] = $employeesQuery->all();
        $this->castNumericValues($data['employees'], ['id', 'is_active']);

        // 2. Siparişleri warehouse _key ile eşleştiriyoruz.
        // Optimize edilmiş alanları seç - gereksiz alanlar kaldırıldı
        $poQuery = (new Query())
            ->select([
                'id', 'fisno', 'tarih', 'status', 
                '_key_sis_depo_source', '__carikodu', 'created_at', 'updated_at'
            ])
            ->from('siparisler')
            ->where(['_key_sis_depo_source' => $warehouseKey])
            ->andWhere(['in', 'status', [0, 1, 2, 3]]); // Aktif durumlar

        // ########## SATIN ALMA SİPARİS FİŞ İÇİN İNKREMENTAL SYNC ##########
        if ($serverSyncTimestamp) {
            $poQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
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
        $data['wms_putaway_status'] = [];
        $data['goods_receipts'] = [];
        $data['goods_receipt_items'] = [];

        if (!empty($poIds)) {
            // ########## SATIN ALMA SİPARİS FİŞ SATIR İÇİN İNKREMENTAL SYNC ##########
            $poLineQuery = (new Query())
                ->select([
                    'sa.id', 'sa.siparisler_id', 'sa.kartkodu', 'sa.anamiktar',
                    'sa.created_at', 'sa.updated_at', 'sa.status', 'sa.turu',
                    'sa._key_kalemturu'
                ])
                ->from(['sa' => 'siparis_ayrintili'])
                ->where(['in', 'sa.siparisler_id', $poIds])
                ->andWhere(['sa.turu' => '1']); // DÜZELTME: Tablo öneki eklendi
            if ($serverSyncTimestamp) {
                $poLineQuery->andWhere(['>', 'sa.updated_at', $serverSyncTimestamp]); // DÜZELTME: Tablo öneki eklendi
            } else {
            }
            $data['siparis_ayrintili'] = $poLineQuery->all();
            $this->castNumericValues($data['siparis_ayrintili'], ['id', 'siparisler_id', 'status'], ['anamiktar']);

            $poLineIds = array_column($data['siparis_ayrintili'], 'id');
            if (!empty($poLineIds)) {
                // ########## WMS PUTAWAY STATUS İÇİN İNKREMENTAL SYNC ##########
                $putawayQuery = (new Query())->from('wms_putaway_status')->where(['in', 'purchase_order_line_id', $poLineIds]);
                if ($serverSyncTimestamp) {
                    $putawayQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
                }
                $data['wms_putaway_status'] = $putawayQuery->all();
                $this->castNumericValues($data['wms_putaway_status'], ['id', 'purchase_order_line_id'], ['putaway_quantity']);
            }

            // ########## GOODS RECEIPTS İÇİN İNKREMENTAL SYNC ##########
            $poReceiptsQuery = (new Query())->select(['goods_receipt_id as id', 'warehouse_id', 'siparis_id', 'invoice_number', 'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])->from('goods_receipts')->where(['in', 'siparis_id', $poIds]);
            if ($serverSyncTimestamp) {
                $poReceiptsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
            }
            $poReceipts = $poReceiptsQuery->all();
            $data['goods_receipts'] = $poReceipts;
        }

        // ########## FREE RECEIPTS İÇİN İNKREMENTAL SYNC ##########
        $freeReceiptsQuery = (new Query())->select(['goods_receipt_id as id', 'warehouse_id', 'siparis_id', 'invoice_number', 'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])->from('goods_receipts')->where(['siparis_id' => null, 'warehouse_id' => $warehouseId]);
        if ($serverSyncTimestamp) {
            $freeReceiptsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
        }
        $freeReceipts = $freeReceiptsQuery->all();
        $data['goods_receipts'] = array_merge($data['goods_receipts'] ?? [], $freeReceipts);

        $this->castNumericValues($data['goods_receipts'], ['id', 'siparis_id', 'employee_id', 'warehouse_id']);

        // ########## GOODS RECEIPT ITEMS İÇİN İNKREMENTAL SYNC ##########
        $receiptIds = array_column($data['goods_receipts'], 'id');
        if (!empty($receiptIds)) {
            $receiptItemsQuery = (new Query())
                ->select(['id', 'receipt_id', 'urun_key', 'siparis_key', 'quantity_received', 'pallet_barcode', 'expiry_date', 'created_at', 'updated_at'])
                ->from('goods_receipt_items')
                ->where(['in', 'receipt_id', $receiptIds]);
            if ($serverSyncTimestamp) {
                $receiptItemsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
            }
            $data['goods_receipt_items'] = $receiptItemsQuery->all();
            $this->castNumericValues($data['goods_receipt_items'], ['id', 'receipt_id'], ['quantity_received']);
        }

        // ########## INVENTORY STOCK İÇİN İNKREMENTAL SYNC ##########
        $locationIds = array_column($data['shelfs'], 'id');
        $stockQuery = (new Query())
            ->select(['id', 'urun_key', 'location_id', 'siparis_id', 'goods_receipt_id', 'quantity', 'pallet_barcode', 'expiry_date', 'stock_status', 'created_at', 'updated_at'])
            ->from('inventory_stock');
        $stockConditions = ['or'];

        if (!empty($locationIds)) {
            $stockConditions[] = ['in', 'location_id', $locationIds];
        }

        $allReceiptIdsForWarehouse = (new Query())
            ->select('goods_receipt_id')
            ->from('goods_receipts')
            ->where(['warehouse_id' => $warehouseId])
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
                $stockQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
            }
        } else {
            $stockQuery->where('1=0');
        }

        $data['inventory_stock'] = $stockQuery->all();
         $this->castNumericValues($data['inventory_stock'], ['id', 'location_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);

        // ########## INVENTORY TRANSFERS İÇİN İNKREMENTAL SYNC ##########
        $transferQuery = (new Query())
            ->select(['id', 'urun_key', 'from_location_id', 'to_location_id', 'quantity', 'from_pallet_barcode', 'pallet_barcode', 'siparis_id', 'goods_receipt_id', 'delivery_note_number', 'employee_id', 'transfer_date', 'created_at', 'updated_at'])
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
                $transferQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
            }
        } else {
            $transferQuery->where('1=0');
        }

        $data['inventory_transfers'] = $transferQuery->all();
        $this->castNumericValues($data['inventory_transfers'], ['id', 'from_location_id', 'to_location_id', 'employee_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);

        return [
            'success' => true,
            'data' => $data,
            'timestamp' => (new \DateTime('now', new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.u\Z'),
            'stats' => [
                'urunler_count' => count($data['urunler'] ?? []),
                'tedarikci_count' => count($data['tedarikci'] ?? []),
                'birimler_count' => count($data['birimler'] ?? []),
                'barkodlar_count' => count($data['barkodlar'] ?? []),
                'inventory_stock_count' => count($data['inventory_stock'] ?? []),
                'inventory_transfers_count' => count($data['inventory_transfers'] ?? []),
                'is_incremental' => !empty($lastSyncTimestamp),
                'last_sync_timestamp' => $lastSyncTimestamp
            ]
        ];

    } catch (\Exception $e) {
        Yii::$app->response->statusCode = 500;
        Yii::error("SyncDownload Hatası: " . $e->getMessage() . "\nTrace: " . $e->getTraceAsString(), __METHOD__);
        return ['success' => false, 'error' => 'Veritabanı indirme sırasında bir hata oluştu: ' . $e->getMessage()];
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
                case 'wms_putaway_status':
                    $data = $this->getPaginatedWmsPutawayStatus($warehouseId, $serverSyncTimestamp, $offset, $limit);
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
            Yii::$app->response->statusCode = 500;
            Yii::error("Paginated download hatası ($tableName): " . $e->getMessage(), __METHOD__);
            return ['success' => false, 'error' => "$tableName tablosu sayfa $page indirilemedi: " . $e->getMessage()];
        }
    }

    public function actionHealthCheck()
    {
        return ['status' => 'ok', 'timestamp' => date('c')];
    }

    // ########## PAGINATED QUERY METHODS ##########
    
    private function getPaginatedUrunler($serverSyncTimestamp, $offset, $limit)
    {
        // TODO: UrunId yerine _key kullanılacak - _key eşsiz ürün tanımlayıcısı
        $query = (new Query())
            ->select(['UrunId as id', 'StokKodu', 'UrunAdi', 'aktif', '_key', 'updated_at'])
            ->from('urunler');

        if ($serverSyncTimestamp) {
            $query->where(['>', 'updated_at', $serverSyncTimestamp]);
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
            $query->where(['>', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);
        $data = $query->all();
        $this->castNumericValues($data, ['id', 'Aktif']);
        return $data;
    }

    private function getPaginatedBirimler($serverSyncTimestamp, $offset, $limit)
    {
        $query = (new Query())
            ->select(['id', 'birimadi', 'birimkod', 'carpan', '_key', '_key_scf_stokkart', 'StokKodu', 
                     'created_at', 'updated_at'])
            ->from('birimler');

        if ($serverSyncTimestamp) {
            $query->where(['>', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id'], ['carpan']);
        return $data;
    }

    private function getPaginatedBarkodlar($serverSyncTimestamp, $offset, $limit)
    {
        $query = (new Query())
            ->select(['id', '_key', '_key_scf_stokkart_birimleri', 'barkod', 'turu', 'created_at', 'updated_at'])
            ->from('barkodlar');

        if ($serverSyncTimestamp) {
            $query->where(['>', 'updated_at', $serverSyncTimestamp]);
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
                     'e.warehouse_code', 'e.is_active', 'e.created_at', 'e.updated_at'])
            ->from(['e' => 'employees'])
            ->where(['e.is_active' => 1, 'e.warehouse_code' => $warehouseCode]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'e.updated_at', $serverSyncTimestamp]);
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
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
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
            ->andWhere(['in', 'status', [0, 1, 2, 3]]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
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
            ->andWhere(['in', 'status', [0, 1, 2, 3]])
            ->column();

        if (empty($poIds)) {
            return [];
        }

        $query = (new Query())
            ->select(['sa.id', 'sa.siparisler_id', 'sa.kartkodu', 'sa.anamiktar',
                     'sa.sipbirimi', 'sa.sipbirimkey', 'sa.created_at', 'sa.updated_at', 'sa.status', 'sa.turu',
                     'sa._key_kalemturu'])
            ->from(['sa' => 'siparis_ayrintili'])
            ->where(['in', 'sa.siparisler_id', $poIds])
            ->andWhere(['sa.turu' => '1']); // FIX: Table prefix added

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'sa.updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'siparisler_id', 'status'], ['anamiktar']);
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

        // Free receipts
        $conditions[] = ['and', ['siparis_id' => null], ['warehouse_id' => $warehouseId]];

        $query = (new Query())
            ->select(['goods_receipt_id as id', 'warehouse_id', 'siparis_id', 'invoice_number', 
                     'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])
            ->from('goods_receipts');

        if (count($conditions) > 1) {
            $query->where($conditions);
        } else {
            return [];
        }

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'siparis_id', 'employee_id', 'warehouse_id']);
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
            ->select(['id', 'receipt_id', 'urun_key', 'siparis_key', 'quantity_received', 'pallet_barcode', 'expiry_date', 'created_at', 'updated_at'])
            ->from('goods_receipt_items')
            ->where(['in', 'receipt_id', $receiptIds]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'receipt_id'], ['quantity_received']);
        return $data;
    }

    private function getPaginatedInventoryStock($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        $locationIds = (new Query())
            ->select('id')
            ->from('shelfs')
            ->where(['warehouse_id' => $warehouseId])
            ->column();

        $allReceiptIds = $this->getReceiptIdsForWarehouse($warehouseId);

        $stockConditions = ['or'];

        if (!empty($locationIds)) {
            $stockConditions[] = ['in', 'location_id', $locationIds];
        }

        if (!empty($allReceiptIds)) {
            $stockConditions[] = [
                'and',
                ['is', 'location_id', new \yii\db\Expression('NULL')],
                ['in', 'goods_receipt_id', $allReceiptIds]
            ];
        }

        if (count($stockConditions) <= 1) {
            return [];
        }

        $query = (new Query())
            ->select(['id', 'urun_key', 'location_id', 'siparis_id', 'goods_receipt_id', 'quantity', 'pallet_barcode', 'expiry_date', 'stock_status', 'created_at', 'updated_at'])
            ->from('inventory_stock')
            ->where($stockConditions);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
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
            ->select(['id', 'urun_key', 'from_location_id', 'to_location_id', 'quantity', 'from_pallet_barcode', 'pallet_barcode', 'siparis_id', 'goods_receipt_id', 'delivery_note_number', 'employee_id', 'transfer_date', 'created_at', 'updated_at'])
            ->from('inventory_transfers')
            ->where($transferConditions);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'from_location_id', 'to_location_id', 'employee_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);
        return $data;
    }

    private function getPaginatedWmsPutawayStatus($warehouseId, $serverSyncTimestamp, $offset, $limit)
    {
        // Get order line IDs for this warehouse
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
            ->column();

        if (empty($poIds)) {
            return [];
        }

        $poLineIds = (new Query())
            ->select('id')
            ->from('siparis_ayrintili')
            ->where(['in', 'siparisler_id', $poIds])
            ->andWhere(['siparis_ayrintili.turu' => '1']) // DÜZELTME: Tablo öneki eklendi
            ->column();

        if (empty($poLineIds)) {
            return [];
        }

        $query = (new Query())
            ->from('wms_putaway_status')
            ->where(['in', 'purchase_order_line_id', $poLineIds]);

        if ($serverSyncTimestamp) {
            $query->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
        }

        $query->offset($offset)->limit($limit);

        $data = $query->all();
        $this->castNumericValues($data, ['id', 'purchase_order_line_id'], ['putaway_quantity']);
        return $data;
    }

    // Helper method to get receipt IDs for a warehouse
    private function getReceiptIdsForWarehouse($warehouseId)
    {
        return (new Query())
            ->select('goods_receipt_id')
            ->from('goods_receipts')
            ->where(['warehouse_id' => $warehouseId])
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
        $warehouseId = $params['warehouse_id'] ?? null;

        if ($warehouseId === null) {
            return ['success' => false, 'message' => 'Warehouse ID is required.'];
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
            ->andWhere(['gr.warehouse_id' => $warehouseId])
            ->groupBy(['gr.goods_receipt_id', 'gr.delivery_note_number', 'gr.receipt_date', 'e.first_name', 'e.last_name'])
            ->orderBy(['gr.receipt_date' => SORT_DESC])
            ->all();

        return ['success' => true, 'data' => $receipts];
    }
}