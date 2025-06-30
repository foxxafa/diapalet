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
        $params = Yii::$app->request->getBodyParams();
        $username = $params['username'] ?? null;
        $password = $params['password'] ?? null;

        if (!$username || !$password) {
            Yii::$app->response->statusCode = 400;
            return ['status' => 400, 'message' => 'Kullanıcı adı ve şifre gereklidir.'];
        }

        try {
            $user = (new Query())
                ->from('employees')
                ->where(['username' => $username, 'password' => $password, 'is_active' => 1])
                ->one();

            if ($user) {
                $apiKey = Yii::$app->security->generateRandomString();
                $userData = [
                    'id' => (int)$user['id'],
                    'first_name' => $user['first_name'],
                    'last_name' => $user['last_name'],
                    'warehouse_id' => (int)($user['warehouse_id'] ?? 0),
                    'username' => $user['username'],
                ];
                return [
                    'status' => 200, 'message' => 'Giriş başarılı.',
                    'user' => $userData, 'apikey' => $apiKey
                ];
            } else {
                Yii::$app->response->statusCode = 401;
                return ['status' => 401, 'message' => 'Kullanıcı adı veya şifre hatalı.'];
            }
        } catch (\yii\db\Exception $e) {
            Yii::error("Login DB Hatası: " . $e->getMessage(), __METHOD__);
            Yii::$app->response->statusCode = 500;
            return ['status' => 500, 'message' => 'Sunucu tarafında bir hata oluştu.'];
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
                        'local_id' => (int)$localId, // Flutter tarafında bu isim bekleniyor
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
                    
                    $results[] = ['local_id' => $localId, 'result' => $result];
                } else {
                    throw new \Exception("İşlem (ID: {$localId}, Tip: {$opType}) başarısız: " . ($result['message'] ?? 'Bilinmeyen hata'));
                }
            }

            $transaction->commit();
            return ['success' => true, 'results' => $results];

        } catch (\Exception $e) {
            $transaction->rollBack();
            Yii::error("SyncUpload Toplu İşlem Hatası: {$e->getMessage()}\nTrace: {$e->getTraceAsString()}", __METHOD__);
            Yii::$app->response->setStatusCode(500);
            return ['success' => false, 'error' => 'İşlem sırasında bir hata oluştu ve geri alındı.', 'details' => $e->getMessage()];
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
            ])->execute();
            // Sipariş varsa 'receiving', yoksa (serbest kabul) 'available' olarak ekle
            $stockStatus = $siparisId ? 'receiving' : 'available';
            $this->upsertStock($db, $item['urun_id'], 1, $item['quantity'], $item['pallet_barcode'] ?? null, $stockStatus, $siparisId);
        }

        if ($siparisId) {
            $this->checkAndFinalizeReceiptStatus($db, $siparisId);
        }

        return ['status' => 'success', 'receipt_id' => $receiptId];
    }

    private function _createInventoryTransfer($data, $db) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || !isset($header['employee_id'], $header['source_location_id'], $header['target_location_id'])) {
            return ['status' => 'error', 'message' => 'Geçersiz transfer verisi.'];
        }

        $sourceLocationId = $header['source_location_id'];
        $operationType = $header['operation_type'] ?? 'box_transfer';
        $siparisId = $header['siparis_id'] ?? null;
        // Yerleştirme operasyonu, kaynak lokasyon 1 (Mal Kabul Alanı) ise ve sipariş ID'si varsa geçerlidir.
        $isPutawayOperation = ($sourceLocationId == 1 && $siparisId != null);

        foreach ($items as $item) {
            $productId = $item['product_id'];
            $quantity = (float)$item['quantity'];
            $sourcePallet = $item['pallet_id'] ?? null;
            $targetPallet = ($operationType === 'pallet_transfer') ? $sourcePallet : null;

            // Kaynaktan düş
            $this->upsertStock($db, $productId, $sourceLocationId, -$quantity, $sourcePallet, $isPutawayOperation ? 'receiving' : 'available', $isPutawayOperation ? $siparisId : null);
            // Hedefe ekle
            $this->upsertStock($db, $productId, $header['target_location_id'], $quantity, $targetPallet, 'available');

            $transferData = [
                'urun_id' => $productId, 'from_location_id' => $sourceLocationId,
                'to_location_id' => $header['target_location_id'], 'quantity' => $quantity,
                'from_pallet_barcode' => $sourcePallet, 'pallet_barcode' => $targetPallet,
                'employee_id' => $header['employee_id'], 'transfer_date' => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
            ];

            if ($isPutawayOperation) {
                $orderLine = (new Query())->from('satin_alma_siparis_fis_satir')->where(['siparis_id' => $siparisId, 'urun_id' => $productId])->one($db);
                if ($orderLine) {
                    $orderLineId = $orderLine['id'];
                    // $transferData['satin_alma_siparis_fis_satir_id'] = $orderLineId; // Bu tabloya bu veri yazılmamalı.

                    // wms_putaway_status tablosuna ekleme/güncelleme yap
                    $sql = "INSERT INTO wms_putaway_status (satin_alma_siparis_fis_satir_id, putaway_quantity) VALUES (:line_id, :qty) ON DUPLICATE KEY UPDATE putaway_quantity = putaway_quantity + VALUES(putaway_quantity)";
                    $db->createCommand($sql, [':line_id' => $orderLineId, ':qty' => $quantity])->execute();
                }
            }
            $db->createCommand()->insert('inventory_transfers', $transferData)->execute();
        }

        if ($isPutawayOperation) {
            $this->checkAndFinalizePoStatus($db, $siparisId);
        }

        return ['status' => 'success'];
    }

    private function upsertStock($db, $urunId, $locationId, $qtyChange, $palletBarcode, $stockStatus, $siparisId = null) {
        $sql = "SELECT * FROM inventory_stock WHERE urun_id = :urun_id AND location_id = :location_id AND stock_status = :stock_status";
        $params = [':urun_id' => $urunId, ':location_id' => $locationId, ':stock_status' => $stockStatus];
        
        if ($palletBarcode === null) {
            $sql .= " AND pallet_barcode IS NULL";
        } else {
            $sql .= " AND pallet_barcode = :pallet_barcode";
            $params[':pallet_barcode'] = $palletBarcode;
        }

        if ($siparisId === null) {
            $sql .= " AND siparis_id IS NULL";
        } else {
            $sql .= " AND siparis_id = :siparis_id";
            $params[':siparis_id'] = $siparisId;
        }

        $sql .= " FOR UPDATE";
        $stock = $db->createCommand($sql, $params)->queryOne();

        if ($stock) {
            $newQty = (float)($stock['quantity']) + (float)$qtyChange;
            if ($newQty > 0.001) {
                $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $stock['id']])->execute();
            } else {
                $db->createCommand()->delete('inventory_stock', ['id' => $stock['id']])->execute();
            }
        } elseif ($qtyChange > 0) {
            $db->createCommand()->insert('inventory_stock', [
                'urun_id' => $urunId, 'location_id' => $locationId, 'quantity' => (float)$qtyChange,
                'pallet_barcode' => $palletBarcode, 'stock_status' => $stockStatus, 'siparis_id' => $siparisId
            ])->execute();
        } else {
            throw new \Exception("Stok düşürme hatası: Kaynakta yeterli veya uygun statüde ürün bulunamadı.");
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
            ->leftJoin(['w' => 'wms_putaway_status'], 's.id = w.satin_alma_siparis_fis_satir_id')
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

            $data['warehouses_shelfs'] = (new Query())->from('warehouses_shelfs')->where(['warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['warehouses_shelfs'], ['id', 'warehouse_id', 'is_active']);

            $employeeColumns = ['id', 'first_name', 'last_name', 'username', 'password', 'warehouse_id', 'is_active', 'created_at', 'updated_at'];
            $data['employees'] = (new Query())->select($employeeColumns)->from('employees')->where(['is_active' => 1, 'warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['employees'], ['id', 'warehouse_id', 'is_active']);

            // Sadece status değeri 5'ten küçük olan (Yani tamamen kaybolmamış) siparişleri indir
            $poQuery = (new Query())->from('satin_alma_siparis_fis')->where(['lokasyon_id' => $warehouseId])->andWhere(['<', 'status', 5]);
            $data['satin_alma_siparis_fis'] = $poQuery->all();
            
            // DEBUG: Kaç sipariş bulundu?
            Yii::info("Warehouse $warehouseId için " . count($data['satin_alma_siparis_fis']) . " adet sipariş bulundu.", __METHOD__);
            foreach ($data['satin_alma_siparis_fis'] as $order) {
                Yii::info("Sipariş ID: {$order['id']}, Status: {$order['status']}, PO ID: {$order['po_id']}", __METHOD__);
            }
            
            $this->castNumericValues($data['satin_alma_siparis_fis'], ['id', 'lokasyon_id', 'status']);

            $poIds = array_column($data['satin_alma_siparis_fis'], 'id');
            if (!empty($poIds)) {
                $data['satin_alma_siparis_fis_satir'] = (new Query())->from('satin_alma_siparis_fis_satir')->where(['in', 'siparis_id', $poIds])->all();
                $this->castNumericValues($data['satin_alma_siparis_fis_satir'], ['id', 'siparis_id', 'urun_id'], ['miktar']);

                // Yeni eklenen kısım: wms_putaway_status verilerini çek
                $poLineIds = array_column($data['satin_alma_siparis_fis_satir'], 'id');
                if (!empty($poLineIds)) {
                    $data['wms_putaway_status'] = (new Query())->from('wms_putaway_status')->where(['in', 'satin_alma_siparis_fis_satir_id', $poLineIds])->all();
                    $this->castNumericValues($data['wms_putaway_status'], ['id', 'satin_alma_siparis_fis_satir_id'], ['putaway_quantity']);
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

            // Sadece Mal Kabul(1) ve ilgili depo lokasyonlarındaki stokları indir
            $locationIds = array_column($data['warehouses_shelfs'], 'id');
            $locationIds[] = 1; // Mal Kabul lokasyonunu ekle

            if (!empty($locationIds)) {
                $data['inventory_stock'] = (new Query())->from('inventory_stock')->where(['in', 'location_id', $locationIds])->all();
                
                // DEBUG: Kaç inventory stock kaydı bulundu?
                Yii::info("Inventory stock kayıt sayısı: " . count($data['inventory_stock']), __METHOD__);
                foreach ($data['inventory_stock'] as $stock) {
                    Yii::info("Stock: ID {$stock['id']}, Urun ID: {$stock['urun_id']}, Location: {$stock['location_id']}, Status: {$stock['stock_status']}, Siparis: {$stock['siparis_id']}", __METHOD__);
                }
                
                 $this->castNumericValues($data['inventory_stock'], ['id', 'urun_id', 'location_id', 'siparis_id'], ['quantity']);
            } else {
                $data['inventory_stock'] = [];
            }

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