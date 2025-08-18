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
            // Rowhub formatında login sorgusu
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
        $deliveryNoteNumber = $header['delivery_note_number'] ?? null;

        // Serbest mal kabulde fiş numarası zorunludur.
        if ($siparisId === null && empty($deliveryNoteNumber)) {
            return ['status' => 'error', 'message' => 'Serbest mal kabul için irsaliye numarası (delivery_note_number) zorunludur.'];
        }

        // Employee'nin warehouse_id'sini al - Rowhub formatında
        $employeeId = $header['employee_id'];
        $employeeWarehouseQuery = (new Query())
            ->select('w.id')
            ->from(['e' => 'employees'])
            ->leftJoin(['w' => 'warehouses'], 'e.warehouse_code = w.warehouse_code')
            ->where(['e.id' => $employeeId]);

        $warehouseId = $employeeWarehouseQuery->scalar($db);

        if (!$warehouseId) {
            return ['status' => 'error', 'message' => 'Çalışanın warehouse bilgisi bulunamadı.'];
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
            $db->createCommand()->insert('goods_receipt_items', [
                'receipt_id' => $receiptId, 'urun_id' => $item['urun_id'],
                'quantity_received' => $item['quantity'], 'pallet_barcode' => $item['pallet_barcode'] ?? null,
                'expiry_date' => $item['expiry_date'] ?? null,
            ])->execute();

            // DÜZELTME: Stok, fiziksel bir 'Mal Kabul' rafına değil, location_id'si NULL olan
            // sanal bir alana eklenir.
            $stockStatus = 'receiving'; // For all goods receipts, stock should initially be in 'receiving' status.
            $this->upsertStock($db, $item['urun_id'], null, $item['quantity'], $item['pallet_barcode'] ?? null, $stockStatus, $siparisId, $item['expiry_date'] ?? null, $receiptId);
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

        // A putaway operation is any transfer from the virtual receiving area (source_location_id is NULL)
        $isPutawayOperation = ($sourceLocationId === null);
        $sourceStatus = $isPutawayOperation ? 'receiving' : 'available';

        foreach ($items as $item) {
            $productId = $item['product_id'];
            $totalQuantityToTransfer = (float)$item['quantity'];
            $sourcePallet = $item['pallet_id'] ?? null;
            $targetPallet = ($operationType === 'pallet_transfer') ? $sourcePallet : null;

            // 1. Find source stocks using FIFO logic
            $sourceStocksQuery = new Query();
            $sourceStocksQuery->from('inventory_stock')
                ->where(['urun_id' => $productId, 'stock_status' => $sourceStatus]);
            $this->addNullSafeWhere($sourceStocksQuery, 'location_id', $sourceLocationId);
            $this->addNullSafeWhere($sourceStocksQuery, 'pallet_barcode', $sourcePallet);

            // For putaway operations, we must filter by the specific order or receipt
            if ($isPutawayOperation) {
                if ($siparisId) {
                    $this->addNullSafeWhere($sourceStocksQuery, 'siparis_id', $siparisId);
                } elseif ($deliveryNoteNumber) {
                    // Serbest mal kabul için delivery note üzerinden receipt ID bulun
                    $actualGoodsReceiptId = (new Query())
                        ->select('goods_receipt_id')
                        ->from('goods_receipts')
                        ->where(['delivery_note_number' => $deliveryNoteNumber])
                        ->scalar($db);
                    if ($actualGoodsReceiptId) {
                        $this->addNullSafeWhere($sourceStocksQuery, 'goods_receipt_id', $actualGoodsReceiptId);
                        // errorContext ve sonraki işlemler için goodsReceiptId'i güncelle
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
                return ['status' => 'error', 'message' => "Yetersiz stok. Ürün ID: {$productId}, Mevcut: {$totalAvailable}, İstenen: {$totalQuantityToTransfer}. Context: {$errorContext}"];
            }

            // 2. Determine portions to transfer and the required DB operations
            $quantityLeft = $totalQuantityToTransfer;
            $portionsToTransfer = []; // {qty, expiry, siparis_id, goods_receipt_id}
            $dbOps = ['delete' => [], 'update' => []]; // {id: new_qty}

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
                    $dbOps['update'][$stockId] = $stockQty - $qtyThisCycle;
                } else {
                    $dbOps['delete'][] = $stockId;
                }
                $quantityLeft -= $qtyThisCycle;
            }

            // 3. Execute DB operations (Decrement source)
            if (!empty($dbOps['delete'])) {
                $db->createCommand()->delete('inventory_stock', ['in', 'id', $dbOps['delete']])->execute();
            }
            foreach ($dbOps['update'] as $id => $newQty) {
                $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $id])->execute();
            }

            // 4. Add portions to target (preserving expiry dates and source IDs)
            foreach($portionsToTransfer as $portion) {
                $this->upsertStock(
                    $db,
                    $productId,
                    $targetLocationId,
                    $portion['qty'],
                    $targetPallet,
                    'available',
                    // GÜNCELLEME: Null yerine kaynak stoktaki ID'leri gönderiyoruz
                    $portion['siparis_id'],
                    $portion['expiry'],
                    $portion['goods_receipt_id']
                );

                // 5. Create a separate transfer record for each portion
                $transferData = [
                    'urun_id'             => $productId,
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

            // 6. Update putaway status for order-based operations
            if ($isPutawayOperation && $siparisId) {
                 // kartkodu ile ürün bulup sipariş satırını bul  
                 $productCode = (new Query())->select('StokKodu')->from('urunler')->where(['UrunId' => $productId])->scalar($db);
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

    private function upsertStock($db, $urunId, $locationId, $qtyChange, $palletBarcode, $stockStatus, $siparisId = null, $expiryDate = null, $goodsReceiptId = null) {
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
            $this->addNullSafeWhere($availabilityQuery, 'goods_receipt_id', $goodsReceiptId);
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
                  ->where(['urun_id' => $urunId, 'stock_status' => $stockStatus]);

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
                $db->createCommand()->insert('inventory_stock', [
                    'urun_id' => $urunId, 'location_id' => $locationId, 'siparis_id' => $siparisId,
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
                u.UrunId,
                (SELECT COALESCE(SUM(gri.quantity_received), 0)
                 FROM goods_receipt_items gri
                 JOIN goods_receipts gr ON gr.goods_receipt_id = gri.receipt_id
                 WHERE gr.siparis_id = :siparis_id AND gri.urun_id = u.UrunId
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

    public function actionSyncDownload()
{
    $payload = $this->getJsonBody();
    $warehouseId = $payload['warehouse_id'] ?? null;
    $lastSyncTimestamp = $payload['last_sync_timestamp'] ?? null; // <<<--- YENİ PARAMETRE

    if (!$warehouseId) {
        Yii::$app->response->statusCode = 400;
        return ['success' => false, 'error' => 'Depo ID (warehouse_id) zorunludur.'];
    }
    $warehouseId = (int)$warehouseId;

    // ########## UTC TIMESTAMP KULLANIMI ##########
    // Global kullanım için UTC timestamp'leri direkt karşılaştır
    $serverSyncTimestamp = $lastSyncTimestamp;
    
    // ÇÖZÜM: ON UPDATE CURRENT_TIMESTAMP sorunu için 30 saniye buffer ekle
    if ($lastSyncTimestamp) {
        $syncDateTime = new \DateTime($lastSyncTimestamp);
        $syncDateTime->sub(new \DateInterval('PT30S')); // 30 saniye çıkar
        $serverSyncTimestamp = $syncDateTime->format('Y-m-d H:i:s');
        
        Yii::info("İnkremental sync: Orijinal timestamp '$lastSyncTimestamp', Buffer ile kullanılan: '$serverSyncTimestamp'", __METHOD__);
    } else {
        Yii::info("Full sync: Tüm veriler alınacak (ilk sync)", __METHOD__);
    }

    try {
        $data = [];

        // Timestamp hazır, direkt kullan

        // ########## İNKREMENTAL SYNC İÇİN ÜRÜNLER ##########
        // ESKİ BARCODE ALANLARI ARTIK KULLANILMIYOR - Yeni barkodlar tablosuna geçildi
        $urunlerQuery = (new Query())
            ->select(['UrunId as id', 'StokKodu', 'UrunAdi', 'aktif', 'updated_at'])
            ->from('urunler');

        // Eğer last_sync_timestamp varsa, sadece o tarihten sonra güncellenen ürünleri al
        if ($serverSyncTimestamp) {
            $urunlerQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp (UTC) tarihinden sonraki ürünler alınıyor.", __METHOD__);
        } else {
            // İlk sync ise tüm aktif ürünleri al
            Yii::info("Full sync: Tüm ürünler alınıyor (ilk sync).", __METHOD__);
        }

        $urunlerData = $urunlerQuery->all();
        $this->castNumericValues($urunlerData, ['id', 'aktif']);
        $data['urunler'] = $urunlerData;

        Yii::info("Ürün sync: " . count($urunlerData) . " ürün gönderiliyor.", __METHOD__);
        // ########## İNKREMENTAL SYNC BİTTİ ##########

        // ########## TEDARİKÇİ İÇİN İNKREMENTAL SYNC ##########
        $tedarikciQuery = (new Query())
            ->select(['id', 'tedarikci_kodu', 'tedarikci_adi', 'Aktif', 'updated_at'])
            ->from('tedarikci');

        // Eğer last_sync_timestamp varsa, sadece o tarihten sonra güncellenen tedarikçileri al
        if ($serverSyncTimestamp) {
            $tedarikciQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki tedarikçiler alınıyor.", __METHOD__);
        } else {
            // İlk sync ise tüm tedarikçileri al
            Yii::info("Full sync: Tüm tedarikçiler alınıyor (ilk sync).", __METHOD__);
        }

        $tedarikciData = $tedarikciQuery->all();
        $this->castNumericValues($tedarikciData, ['id', 'Aktif']);
        $data['tedarikci'] = $tedarikciData;

        Yii::info("Tedarikçi sync: " . count($tedarikciData) . " tedarikçi gönderiliyor.", __METHOD__);
        // ########## TEDARİKÇİ İNKREMENTAL SYNC BİTTİ ##########

        // ########## BİRİMLER İÇİN İNKREMENTAL SYNC ##########
        $birimlerQuery = (new Query())
            ->select(['id', 'birimadi', 'birimkod', 'carpan', 'fiyat1', 'fiyat2', 'fiyat3', 'fiyat4', 'fiyat5', 
                     'fiyat6', 'fiyat7', 'fiyat8', 'fiyat9', 'fiyat10', '_key', '_key_scf_stokkart', 'StokKodu', 
                     'created_at', 'updated_at'])
            ->from('birimler');

        if ($serverSyncTimestamp) {
            $birimlerQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki birimler alınıyor.", __METHOD__);
        } else {
            Yii::info("Full sync: Tüm birimler alınıyor (ilk sync).", __METHOD__);
        }

        $birimlerData = $birimlerQuery->all();
        $this->castNumericValues($birimlerData, ['id'], ['carpan', 'fiyat1', 'fiyat2', 'fiyat3', 'fiyat4', 'fiyat5', 'fiyat6', 'fiyat7', 'fiyat8', 'fiyat9', 'fiyat10']);
        $data['birimler'] = $birimlerData;

        Yii::info("Birimler sync: " . count($birimlerData) . " birim gönderiliyor.", __METHOD__);
        // ########## BİRİMLER İNKREMENTAL SYNC BİTTİ ##########

        // ########## BARKODLAR İÇİN İNKREMENTAL SYNC ##########
        $barkodlarQuery = (new Query())
            ->select(['id', '_key', '_key_scf_stokkart_birimleri', 'barkod', 'turu', 'created_at', 'updated_at'])
            ->from('barkodlar');

        if ($serverSyncTimestamp) {
            $barkodlarQuery->where(['>', 'updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki barkodlar alınıyor.", __METHOD__);
        } else {
            Yii::info("Full sync: Tüm barkodlar alınıyor (ilk sync).", __METHOD__);
        }

        $barkodlarData = $barkodlarQuery->all();
        $this->castNumericValues($barkodlarData, ['id']);
        $data['barkodlar'] = $barkodlarData;

        Yii::info("Barkodlar sync: " . count($barkodlarData) . " barkod gönderiliyor.", __METHOD__);
        // ########## BARKODLAR İNKREMENTAL SYNC BİTTİ ##########

        // ########## SHELFS İÇİN İNKREMENTAL SYNC ##########
        $shelfsQuery = (new Query())
            ->select(['id', 'warehouse_id', 'name', 'code', 'is_active', 'created_at', 'updated_at'])
            ->from('shelfs')
            ->where(['warehouse_id' => $warehouseId]);
        if ($serverSyncTimestamp) {
            $shelfsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki raflar alınıyor.", __METHOD__);
        } else {
            Yii::info("Full sync: Tüm raflar alınıyor (ilk sync).", __METHOD__);
        }
        $data['shelfs'] = $shelfsQuery->all();
        $this->castNumericValues($data['shelfs'], ['id', 'warehouse_id', 'is_active']);

        // warehouse tablosu kaldırıldı - mobil uygulama SharedPreferences kullanıyor

        // ########## EMPLOYEES İÇİN İNKREMENTAL SYNC ##########
        // Rowhub formatında employee sorgusu
        $employeeColumns = [
            'e.id', 'e.first_name', 'e.last_name', 'e.username', 'e.password',
            'e.warehouse_id', 'e.is_active', 'e.created_at', 'e.updated_at'
        ];
        $employeesQuery = (new Query())
            ->select($employeeColumns)
            ->from(['e' => 'employees'])
            ->where(['e.is_active' => 1, 'e.warehouse_id' => $warehouseId]);

        if ($serverSyncTimestamp) {
            $employeesQuery->andWhere(['>', 'e.updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki çalışanlar alınıyor.", __METHOD__);
        } else {
            Yii::info("Full sync: Tüm çalışanlar alınıyor (ilk sync).", __METHOD__);
        }
        $data['employees'] = $employeesQuery->all();
        $this->castNumericValues($data['employees'], ['id', 'warehouse_id', 'is_active']);

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
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki siparişler alınıyor.", __METHOD__);
        } else {
            Yii::info("Full sync: Tüm siparişler alınıyor (ilk sync).", __METHOD__);
        }

        $data['siparisler'] = $poQuery->all();
        
        // notlar alanını null olarak ekle çünkü server DB'de yok ama client'da kullanılıyor
        foreach ($data['siparisler'] as &$siparis) {
            $siparis['notlar'] = null;
        }
        // ########## UYARLAMA BİTTİ ##########

        Yii::info("Warehouse $warehouseId (Name: $warehouseName, Code: $warehouseCode, Key: $warehouseKey) için " . count($data['siparisler']) . " adet sipariş bulundu.", __METHOD__);
        
        // DEBUG: Sipariş olmadığında debug bilgisi
        if (empty($data['siparisler'])) {
            Yii::info("DEBUG: Sipariş bulunamadı. Kontrol için tüm siparişleri sorguluyoruz...", __METHOD__);
            $allOrdersQuery = (new Query())->select(['count(*) as total'])->from('siparisler');
            $allOrdersCount = $allOrdersQuery->scalar();
            Yii::info("DEBUG: Toplam sipariş sayısı: $allOrdersCount", __METHOD__);
            
            $ordersWithKeyQuery = (new Query())->select(['count(*) as total'])->from('siparisler')->where(['_key_sis_depo_source' => $warehouseKey]);
            $ordersWithKeyCount = $ordersWithKeyQuery->scalar();
            Yii::info("DEBUG: Warehouse key '$warehouseKey' ile eşleşen sipariş sayısı: $ordersWithKeyCount", __METHOD__);
            
            // Eğer _key_sis_depo_source sütunu yoksa hata atacak
            try {
                $sampleOrderQuery = (new Query())->select(['id', '_key_sis_depo_source'])->from('siparisler')->limit(5);
                $sampleOrders = $sampleOrderQuery->all();
                Yii::info("DEBUG: Örnek siparişlerin _key_sis_depo_source değerleri: " . json_encode($sampleOrders), __METHOD__);
            } catch (\Exception $e) {
                Yii::info("DEBUG: _key_sis_depo_source sütunu bulunamadı: " . $e->getMessage(), __METHOD__);
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
                    'id', 'siparisler_id', 'kartkodu', 'anamiktar', 'miktar',
                    'anabirimi', 'created_at', 'updated_at', 'status', 'turu'
                ])
                ->from('siparis_ayrintili')
                ->where(['in', 'siparisler_id', $poIds])
                ->andWhere(['turu' => '1']);
            if ($serverSyncTimestamp) {
                $poLineQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
                Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki sipariş kalemleri alınıyor.", __METHOD__);
            } else {
                Yii::info("Full sync: Tüm sipariş kalemleri alınıyor (ilk sync).", __METHOD__);
            }
            $data['siparis_ayrintili'] = $poLineQuery->all();
            $this->castNumericValues($data['siparis_ayrintili'], ['id', 'siparisler_id', 'status'], ['anamiktar']);

            $poLineIds = array_column($data['siparis_ayrintili'], 'id');
            if (!empty($poLineIds)) {
                // ########## WMS PUTAWAY STATUS İÇİN İNKREMENTAL SYNC ##########
                $putawayQuery = (new Query())->from('wms_putaway_status')->where(['in', 'purchase_order_line_id', $poLineIds]);
                if ($serverSyncTimestamp) {
                    $putawayQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
                    Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki yerleştirme durumları alınıyor.", __METHOD__);
                }
                $data['wms_putaway_status'] = $putawayQuery->all();
                $this->castNumericValues($data['wms_putaway_status'], ['id', 'purchase_order_line_id'], ['putaway_quantity']);
            }

            // ########## GOODS RECEIPTS İÇİN İNKREMENTAL SYNC ##########
            $poReceiptsQuery = (new Query())->select(['goods_receipt_id as id', 'warehouse_id', 'siparis_id', 'invoice_number', 'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])->from('goods_receipts')->where(['in', 'siparis_id', $poIds]);
            if ($serverSyncTimestamp) {
                $poReceiptsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
                Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki sipariş mal kabulleri alınıyor.", __METHOD__);
            }
            $poReceipts = $poReceiptsQuery->all();
            $data['goods_receipts'] = $poReceipts;
        }

        // ########## FREE RECEIPTS İÇİN İNKREMENTAL SYNC ##########
        $freeReceiptsQuery = (new Query())->select(['goods_receipt_id as id', 'warehouse_id', 'siparis_id', 'invoice_number', 'delivery_note_number', 'employee_id', 'receipt_date', 'created_at', 'updated_at'])->from('goods_receipts')->where(['siparis_id' => null, 'warehouse_id' => $warehouseId]);
        if ($serverSyncTimestamp) {
            $freeReceiptsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
            Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki serbest mal kabulleri alınıyor.", __METHOD__);
        }
        $freeReceipts = $freeReceiptsQuery->all();
        $data['goods_receipts'] = array_merge($data['goods_receipts'] ?? [], $freeReceipts);

        $this->castNumericValues($data['goods_receipts'], ['id', 'siparis_id', 'employee_id', 'warehouse_id']);

        // ########## GOODS RECEIPT ITEMS İÇİN İNKREMENTAL SYNC ##########
        $receiptIds = array_column($data['goods_receipts'], 'id');
        if (!empty($receiptIds)) {
            $receiptItemsQuery = (new Query())->from('goods_receipt_items')->where(['in', 'receipt_id', $receiptIds]);
            if ($serverSyncTimestamp) {
                $receiptItemsQuery->andWhere(['>', 'updated_at', $serverSyncTimestamp]);
                Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki mal kabul kalemleri alınıyor.", __METHOD__);
            }
            $data['goods_receipt_items'] = $receiptItemsQuery->all();
            $this->castNumericValues($data['goods_receipt_items'], ['id', 'receipt_id', 'urun_id'], ['quantity_received']);
        }

        // ########## INVENTORY STOCK İÇİN İNKREMENTAL SYNC ##########
        $locationIds = array_column($data['shelfs'], 'id');
        $stockQuery = (new Query())->from('inventory_stock');
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
                Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki stok kayıtları alınıyor.", __METHOD__);
            }
        } else {
            $stockQuery->where('1=0');
        }

        $data['inventory_stock'] = $stockQuery->all();
         $this->castNumericValues($data['inventory_stock'], ['id', 'urun_id', 'location_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);

        // ########## INVENTORY TRANSFERS İÇİN İNKREMENTAL SYNC ##########
        $transferQuery = (new Query())->from('inventory_transfers');
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
                Yii::info("İnkremental sync: $serverSyncTimestamp tarihinden sonraki transfer kayıtları alınıyor.", __METHOD__);
            }
        } else {
            $transferQuery->where('1=0');
        }

        $data['inventory_transfers'] = $transferQuery->all();
        $this->castNumericValues($data['inventory_transfers'], ['id', 'urun_id', 'from_location_id', 'to_location_id', 'employee_id', 'siparis_id', 'goods_receipt_id'], ['quantity']);

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

    public function actionHealthCheck()
    {
        return ['status' => 'ok', 'timestamp' => date('c')];
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
                'COUNT(DISTINCT ist.urun_id) as item_count'
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