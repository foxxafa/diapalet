<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;
use yii\web\Response;
use yii\db\Transaction;
use yii\db\Query;
use app\components\DepoComponent;

class TerminalController extends Controller
{
    public function beforeAction($action)
    {
        Yii::$app->response->format = Response::FORMAT_JSON;
        $this->enableCsrfValidation = false;

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
            Yii::$app->response->statusCode = 401;
            echo json_encode(['success' => false, 'error' => 'Yetkisiz erişim: API anahtarı eksik veya geçersiz.']);
            Yii::$app->end();
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
            $userQuery = (new Query())
                ->select([
                    'e.id', 'e.first_name', 'e.last_name', 'e.username',
                    'e.warehouse_id', 'w.warehouse_code', 'w.name as warehouse_name',
                    'b.id as branch_id', 'b.name as branch_name'
                ])
                ->from(['e' => 'employees'])
                ->leftJoin(['w' => 'warehouses'], 'e.warehouse_id = w.id')
                ->leftJoin(['b' => 'branches'], 'w.branch_id = b.id')
                ->where(['e.username' => $username, 'e.password' => $password, 'e.is_active' => 1]);

            $user = $userQuery->one();

            if ($user) {
                $apiKey = Yii::$app->security->generateRandomString();
                $userData = [
                    'id' => (int)$user['id'],
                    'first_name' => $user['first_name'],
                    'last_name' => $user['last_name'],
                    'username' => $user['username'],
                    'warehouse_id' => (int)($user['warehouse_id'] ?? 0),
                    'warehouse_name' => $user['warehouse_name'],
                    'warehouse_code' => $user['warehouse_code'],
                    'branch_id' => (int)($user['branch_id'] ?? 0),
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
            return $this->asJson(['status' => 500, 'message' => 'Sunucu tarafında bir hata oluştu.']);
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

        // İşlem sayısını logla
        Yii::info("SyncUpload başlıyor: " . count($operations) . " işlem", __METHOD__);

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
                    Yii::info("İşlem zaten işlenmiş (idempotency): $idempotencyKey", __METHOD__);
                    continue; // Sonraki operasyona geç
                }

                // 3. Yeni işlem ise, operasyonu işle.
                $opType = $op['type'] ?? 'unknown';
                $opData = $op['data'] ?? [];
                $result = ['status' => 'error', 'message' => "Bilinmeyen operasyon tipi: {$opType}"];

                Yii::info("İşlem işleniyor: ID=$localId, Tip=$opType", __METHOD__);

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
                    Yii::info("İşlem başarılı: ID=$localId", __METHOD__);
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
            Yii::info("SyncUpload başarılı: " . count($results) . " işlem tamamlandı", __METHOD__);
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

    private function _createGoodsReceipt($data, $db) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || empty($header['employee_id'])) {
            return ['status' => 'error', 'message' => 'Geçersiz mal kabul verisi.'];
        }

        $siparisId = $header['siparis_id'] ?? null;
        $db->createCommand()->insert('goods_receipts', [
            'siparis_id' => $siparisId,
            'invoice_number' => $header['invoice_number'] ?? null,
            'employee_id' => $header['employee_id'],
            'receipt_date' => $header['receipt_date'] ?? new \yii\db\Expression('NOW()'),
        ])->execute();
        $receiptId = $db->getLastInsertID();

        foreach ($items as $item) {
            $db->createCommand()->insert('goods_receipt_items', [
                'receipt_id' => $receiptId, 'urun_id' => $item['urun_id'],
                'quantity_received' => $item['quantity'], 'pallet_barcode' => $item['pallet_barcode'] ?? null,
                'expiry_date' => $item['expiry_date'] ?? null,
            ])->execute();

            // DÜZELTME: Stok, fiziksel bir 'Mal Kabul' rafına değil, location_id'si NULL olan
            // sanal bir alana eklenir.
            $stockStatus = $siparisId ? 'receiving' : 'available';
            $this->upsertStock($db, $item['urun_id'], null, $item['quantity'], $item['pallet_barcode'] ?? null, $stockStatus, $siparisId, $item['expiry_date'] ?? null);
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
        $operationType = $header['operation_type'] ?? 'box_transfer';
        $siparisId = $header['siparis_id'] ?? null;
        $isPutawayOperation = ($sourceLocationId === null && $siparisId != null);
        $sourceStatus = $isPutawayOperation ? 'receiving' : 'available';

        foreach ($items as $item) {
            $productId = $item['product_id'];
            $totalQuantityToTransfer = (float)$item['quantity'];
            $sourcePallet = $item['pallet_id'] ?? null;
            $targetPallet = ($operationType === 'pallet_transfer') ? $sourcePallet : null;

            // 1. Kaynak stokları FIFO'ya göre bul
            $sourceStocksQuery = new Query();
            $sourceStocksQuery->from('inventory_stock')
                ->where(['urun_id' => $productId, 'stock_status' => $sourceStatus]);
            $this->addNullSafeWhere($sourceStocksQuery, 'location_id', $sourceLocationId);
            $this->addNullSafeWhere($sourceStocksQuery, 'pallet_barcode', $sourcePallet);
            $this->addNullSafeWhere($sourceStocksQuery, 'siparis_id', $siparisId);
            $sourceStocksQuery->orderBy(['expiry_date' => SORT_ASC]);
            $sourceStocks = $sourceStocksQuery->all($db);

            $totalAvailable = array_sum(array_column($sourceStocks, 'quantity'));
            if ($totalAvailable < $totalQuantityToTransfer - 0.001) {
                return ['status' => 'error', 'message' => "Yetersiz stok. Ürün ID: {$productId}, Mevcut: {$totalAvailable}, İstenen: {$totalQuantityToTransfer}"];
            }

            // 2. Transfer edilecek porsiyonları ve yapılacak DB işlemlerini belirle
            $quantityLeft = $totalQuantityToTransfer;
            $portionsToTransfer = []; // {qty, expiry}
            $dbOps = ['delete' => [], 'update' => []]; // {id: new_qty}

            foreach ($sourceStocks as $stock) {
                if ($quantityLeft <= 0.001) break;

                $stockId = $stock['id'];
                $stockQty = (float)$stock['quantity'];
                $qtyThisCycle = min($stockQty, $quantityLeft);

                $portionsToTransfer[] = ['qty' => $qtyThisCycle, 'expiry' => $stock['expiry_date']];

                if ($stockQty - $qtyThisCycle > 0.001) {
                    $dbOps['update'][$stockId] = $stockQty - $qtyThisCycle;
                } else {
                    $dbOps['delete'][] = $stockId;
                }
                $quantityLeft -= $qtyThisCycle;
            }
            
            // 3. Belirlenen DB işlemlerini gerçekleştir (Kaynak Düşürme)
            if (!empty($dbOps['delete'])) {
                $db->createCommand()->delete('inventory_stock', ['in', 'id', $dbOps['delete']])->execute();
            }
            foreach ($dbOps['update'] as $id => $newQty) {
                $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $id])->execute();
            }

            // 4. Porsiyonları hedefe ekle (SKT'leri koruyarak)
            foreach($portionsToTransfer as $portion) {
                // Not: upsertStock'un ekleme kısmı burada yeniden kullanılıyor.
                $this->upsertStock($db, $productId, $targetLocationId, $portion['qty'], $targetPallet, 'available', null, $portion['expiry']);
                
                // 5. Her porsiyon için ayrı transfer kaydı oluştur.
                 $db->createCommand()->insert('inventory_transfers', [
                    'urun_id' => $productId, 'from_location_id' => $sourceLocationId,
                    'to_location_id' => $targetLocationId, 'quantity' => $portion['qty'],
                    'from_pallet_barcode' => $sourcePallet, 'pallet_barcode' => $targetPallet,
                    'employee_id' => $header['employee_id'], 'transfer_date' => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
                ])->execute();
            }
            
            // 6. Rafa yerleştirme durumunu toplam miktar üzerinden güncelle
            if ($isPutawayOperation) {
                 $orderLine = (new Query())->from('satin_alma_siparis_fis_satir')->where(['siparis_id' => $siparisId, 'urun_id' => $productId])->one($db);
                 if ($orderLine) {
                     $orderLineId = $orderLine['id'];
                     $sql = "INSERT INTO wms_putaway_status (satinalmasiparisfissatir_id, putaway_quantity) VALUES (:line_id, :qty) ON DUPLICATE KEY UPDATE putaway_quantity = putaway_quantity + VALUES(putaway_quantity)";
                     $db->createCommand($sql, [':line_id' => $orderLineId, ':qty' => $totalQuantityToTransfer])->execute();
                 }
            }
        }

        if ($isPutawayOperation && $siparisId) {
            $this->checkAndFinalizePoStatus($db, $siparisId);
        }

        return ['status' => 'success'];
    }

    private function upsertStock($db, $urunId, $locationId, $qtyChange, $palletBarcode, $stockStatus, $siparisId = null, $expiryDate = null) {
        $isDecrement = (float)$qtyChange < 0;

        if ($isDecrement) {
            // Bu fonksiyon artık _createInventoryTransfer'da kullanılmıyor,
            // ama diğer yerlerde kullanılma ihtimaline karşı bırakıldı.
            // Mantığı önceki adımdaki gibi (while döngüsü) kalabilir.
            $toDecrement = abs((float)$qtyChange);

            $availabilityQuery = new Query();
            $availabilityQuery->from('inventory_stock')->where(['urun_id' => $urunId, 'stock_status' => $stockStatus]);
            $this->addNullSafeWhere($availabilityQuery, 'location_id', $locationId);
            $this->addNullSafeWhere($availabilityQuery, 'pallet_barcode', $palletBarcode);
            $this->addNullSafeWhere($availabilityQuery, 'siparis_id', $siparisId);
            $totalAvailable = (float)$availabilityQuery->sum('quantity', $db);

            if ($totalAvailable < $toDecrement - 0.001) {
                 throw new \Exception("Stok düşürme hatası: Kaynakta yeterli stok yok. Mevcut: {$totalAvailable}, İstenen: {$toDecrement}");
            }

            while ($toDecrement > 0.001) {
                $query = new Query();
                $query->from('inventory_stock')->where(['urun_id' => $urunId, 'stock_status' => $stockStatus]);
                $this->addNullSafeWhere($query, 'location_id', $locationId);
                $this->addNullSafeWhere($query, 'pallet_barcode', $palletBarcode);
                $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
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
                  ->where(['urun_id' => $urunId, 'stock_status' => $stockStatus]);

            $this->addNullSafeWhere($query, 'location_id', $locationId);
            $this->addNullSafeWhere($query, 'pallet_barcode', $palletBarcode);
            $this->addNullSafeWhere($query, 'siparis_id', $siparisId);
            $this->addNullSafeWhere($query, 'expiry_date', $expiryDate);
            
            $stock = $query->one($db);

            if ($stock) {
                $newQty = (float)($stock['quantity']) + (float)$qtyChange;
                if ($newQty > 0.001) {
                    $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $stock['id']])->execute();
                } else {
                    $db->createCommand()->delete('inventory_stock', ['id' => $stock['id']])->execute();
                }
            } elseif ($qtyChange > 0) {
                $db->createCommand()->insert('inventory_stock', [
                    'urun_id' => $urunId, 'location_id' => $locationId, 'siparis_id' => $siparisId,
                    'quantity' => (float)$qtyChange, 'pallet_barcode' => $palletBarcode, 
                    'stock_status' => $stockStatus, 'expiry_date' => $expiryDate,
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
                (SELECT COALESCE(SUM(gri.quantity_received), 0)
                 FROM goods_receipt_items gri
                 JOIN goods_receipts gr ON gr.id = gri.receipt_id
                 WHERE gr.siparis_id = s.siparis_id AND gri.urun_id = s.urun_id
                ) as received_quantity
            FROM satin_alma_siparis_fis_satir s
            WHERE s.siparis_id = :siparis_id
        ";
        $lines = $db->createCommand($sql, [':siparis_id' => $siparisId])->queryAll();

        if (empty($lines)) return;

        $allLinesCompleted = true;
        $anyLineReceived = false;

        foreach ($lines as $line) {
            $ordered = (float)$line['miktar'];
            $received = (float)$line['received_quantity'];

            if ($received > 0.001) {
                $anyLineReceived = true;
            }
            if ($received < $ordered - 0.001) {
                $allLinesCompleted = false;
            }
        }

        $newStatus = null;
        if ($allLinesCompleted) {
            $newStatus = 2; // Tamamlandı -> Kısmi Kabul olarak değiştirildi. Asıl tamamlama rafa yerleştirme sonrası olacak.
        } elseif ($anyLineReceived) {
            $newStatus = 2; // Kısmi Kabul
        }

        if ($newStatus !== null) {
            $currentStatus = (new Query())->select('status')->from('satin_alma_siparis_fis')->where(['id' => $siparisId])->scalar($db);
            if ($currentStatus != $newStatus) {
                $db->createCommand()->update('satin_alma_siparis_fis', ['status' => $newStatus], ['id' => $siparisId])->execute();
            }
        }
    }

    private function checkAndFinalizePoStatus($db, $siparisId) {
        if (!$siparisId) return;

        // Sipariş satırlarını ve yerleştirilmiş miktarları wms_putaway_status'tan al
        $orderLines = (new Query())
            ->select(['s.id', 's.miktar', 'w.putaway_quantity'])
            ->from(['s' => 'satin_alma_siparis_fis_satir'])
            ->leftJoin(['w' => 'wms_putaway_status'], 's.id = w.satinalmasiparisfissatir_id')
            ->where(['s.siparis_id' => $siparisId])
            ->all($db);

        if (empty($orderLines)) return;

        $allLinesCompleted = true;
        foreach ($orderLines as $line) {
            $ordered = (float)$line['miktar'];
            $putaway = (float)($line['putaway_quantity'] ?? 0);
            if ($putaway < $ordered - 0.001) { // Kayan nokta hataları için tolerans
                $allLinesCompleted = false;
                break;
            }
        }

        if ($allLinesCompleted) {
            // Statü: 4 (Oto. Tamamlandı/Yerleştirildi)
            $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 4], ['id' => $siparisId])->execute();
        }
    }

    private function _forceCloseOrder($data, $db) {
        $siparisId = $data['siparis_id'] ?? null;
        if (empty($siparisId)) {
            return ['status' => 'error', 'message' => 'Geçersiz veri: "siparis_id" eksik.'];
        }
        // Statü: 3 (Manuel Kapatıldı)
        $count = $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 3], ['id' => $siparisId])->execute();

        if ($count > 0) {
            return ['status' => 'success', 'message' => "Order #$siparisId closed."];
        } else {
            return ['status' => 'not_found', 'message' => "Order #$siparisId not found."];
        }
    }

    public function actionSyncDownload()
    {
        $payload = $this->getJsonBody();
        $warehouseId = $payload['warehouse_id'] ?? null;

        if (!$warehouseId) {
            Yii::$app->response->statusCode = 400;
            return ['success' => false, 'error' => 'Depo ID (warehouse_id) zorunludur.'];
        }
        $warehouseId = (int)$warehouseId;

        try {
            $data = [];
            $urunlerData = (new Query())->select(['id' => 'UrunId', 'StokKodu', 'UrunAdi', 'Barcode1', 'aktif'])->from('urunler')->all();
            $this->castNumericValues($urunlerData, ['id', 'aktif']);
            $data['urunler'] = $urunlerData;

            $data['shelfs'] = (new Query())->from('shelfs')->where(['warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['shelfs'], ['id', 'warehouse_id', 'is_active']);

            $employeeColumns = ['id', 'first_name', 'last_name', 'username', 'password', 'warehouse_id', 'is_active', 'created_at', 'updated_at'];
            $data['employees'] = (new Query())->select($employeeColumns)->from('employees')->where(['is_active' => 1, 'warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['employees'], ['id', 'warehouse_id', 'is_active']);

            // Sadece status değeri 5'ten küçük olan (Yani tamamen kaybolmamış) siparişleri indir
            $poQuery = (new Query())->from('satin_alma_siparis_fis')->where(['branch_id' => $warehouseId])->andWhere(['<', 'status', 5]);
            $data['satin_alma_siparis_fis'] = $poQuery->all();
            
            // DEBUG: Kaç sipariş bulundu?
            Yii::info("Warehouse $warehouseId için " . count($data['satin_alma_siparis_fis']) . " adet sipariş bulundu.", __METHOD__);
            foreach ($data['satin_alma_siparis_fis'] as $order) {
                Yii::info("Sipariş ID: {$order['id']}, Status: {$order['status']}, PO ID: {$order['po_id']}", __METHOD__);
            }
            
            $this->castNumericValues($data['satin_alma_siparis_fis'], ['id', 'branch_id', 'status']);

            $poIds = array_column($data['satin_alma_siparis_fis'], 'id');
            if (!empty($poIds)) {
                $data['satin_alma_siparis_fis_satir'] = (new Query())->from('satin_alma_siparis_fis_satir')->where(['in', 'siparis_id', $poIds])->all();
                $this->castNumericValues($data['satin_alma_siparis_fis_satir'], ['id', 'siparis_id', 'urun_id'], ['miktar']);

                // Yeni eklenen kısım: wms_putaway_status verilerini çek
                $poLineIds = array_column($data['satin_alma_siparis_fis_satir'], 'id');
                if (!empty($poLineIds)) {
                    $data['wms_putaway_status'] = (new Query())->from('wms_putaway_status')->where(['in', 'satinalmasiparisfissatir_id', $poLineIds])->all();
                    $this->castNumericValues($data['wms_putaway_status'], ['id', 'satinalmasiparisfissatir_id'], ['putaway_quantity']);
                } else {
                    $data['wms_putaway_status'] = [];
                }

                $data['goods_receipts'] = (new Query())->from('goods_receipts')->where(['in', 'siparis_id', $poIds])->all();
                $this->castNumericValues($data['goods_receipts'], ['id', 'siparis_id', 'employee_id']);

                $receiptIds = array_column($data['goods_receipts'], 'id');
                if (!empty($receiptIds)) {
                    $data['goods_receipt_items'] = (new Query())->from('goods_receipt_items')->where(['in', 'receipt_id', $receiptIds])->all();
                    $this->castNumericValues($data['goods_receipt_items'], ['id', 'receipt_id', 'urun_id'], ['quantity_received']);
                } else {
                    $data['goods_receipt_items'] = [];
                }
            } else {
                 $data['satin_alma_siparis_fis_satir'] = [];
                 $data['goods_receipts'] = [];
                 $data['goods_receipt_items'] = [];
                 $data['wms_putaway_status'] = [];
            }

            // DÜZELTME: Stokları indirirken, ilgili depodaki raflara ek olarak
            // location_id'si NULL olan (Mal Kabul Alanı) stokları da indir.
            $locationIds = array_column($data['shelfs'], 'id');
            
            $stockQuery = (new Query())->from('inventory_stock');
            if (!empty($locationIds)) {
                 $stockQuery->where(['in', 'location_id', $locationIds])
                           ->orWhere(['is', 'location_id', new \yii\db\Expression('NULL')]);
            } else {
                 $stockQuery->where(['is', 'location_id', new \yii\db\Expression('NULL')]);
            }

            $data['inventory_stock'] = $stockQuery->all();
            
            // DEBUG: Kaç inventory stock kaydı bulundu?
            Yii::info("Inventory stock kayıt sayısı: " . count($data['inventory_stock']), __METHOD__);
            foreach ($data['inventory_stock'] as $stock) {
                Yii::info("Stock: ID {$stock['id']}, Urun ID: {$stock['urun_id']}, Location: {$stock['location_id']}, Status: {$stock['stock_status']}, Siparis: {$stock['siparis_id']}", __METHOD__);
            }
            
             $this->castNumericValues($data['inventory_stock'], ['id', 'urun_id', 'location_id', 'siparis_id'], ['quantity']);


            return [
                'success' => true, 'data' => $data,
                'timestamp' => (new \DateTime('now', new \DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.u\Z')
            ];

        } catch (\yii\db\Exception $e) {
            Yii::$app->response->statusCode = 500;
            Yii::error("SyncDownload DB Hatası: " . $e->getMessage(), __METHOD__);
            return ['success' => false, 'error' => 'Veritabanı indirme sırasında bir hata oluştu.'];
        }
    }

    public function actionHealthCheck()
    {
        return ['status' => 'ok', 'timestamp' => date('c')];
    }

    public function actionSyncShelfs()
    {
        $result = DepoComponent::syncWarehousesAndShelfs();
        return $this->asJson($result);
    }
}