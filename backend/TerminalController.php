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
                    'warehouse_id' => (int)$user['warehouse_id'],
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
        $maxRetries = 3;

        for ($i = 0; $i < $maxRetries; $i++) {
            $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);
            try {
                $results = [];
                foreach ($operations as $op) {
                    $opId = $op['id'] ?? null;
                    $opType = $op['type'] ?? 'unknown';
                    
                    if (!$opId) {
                        throw new \Exception("Tüm operasyonlar bir 'id' içermelidir.");
                    }

                    $isProcessed = (new Query())->from('processed_terminal_operations')->where(['operation_id' => $opId])->exists($db);
                    if ($isProcessed) {
                        $results[] = ['operation_id' => $opId, 'result' => ['status' => 'success', 'message' => 'Already processed']];
                        continue;
                    }
                    
                    $opData = $op['data'] ?? [];
                    $result = ['status' => 'error', 'message' => 'Unknown operation'];

                    if ($opType === 'goodsReceipt') {
                        $result = $this->_createGoodsReceipt($opData, $db);
                    } elseif ($opType === 'inventoryTransfer') {
                        $result = $this->_createInventoryTransfer($opData, $db);
                    } elseif ($opType === 'forceCloseOrder') {
                        $result = $this->_forceCloseOrder($opData, $db);
                    } else {
                        $result['message'] = "Bilinmeyen operasyon tipi: {$opType}";
                    }
                    
                    if (isset($result['status']) && $result['status'] === 'success') {
                        $db->createCommand()->insert('processed_terminal_operations', ['operation_id' => $opId])->execute();
                        $results[] = ['operation_id' => $opId, 'result' => $result];
                    } else {
                        throw new \Exception("Operation (ID: {$opId}, Tip: {$opType}) başarısız oldu: " . ($result['message'] ?? 'Bilinmeyen hata'));
                    }
                }
                
                $transaction->commit();
                return ['success' => true, 'results' => $results];

            } catch (\Exception $e) {
                $transaction->rollBack();

                $isDeadlock = false;
                if ($e instanceof \yii\db\Exception && isset($e->errorInfo[1])) {
                    if ($e->errorInfo[1] == 1213) { // 1213 is the MySQL error code for deadlock
                        $isDeadlock = true;
                    }
                }
                
                if (!$isDeadlock) {
                    $errMsg = $e->getMessage();
                    if (strpos($errMsg, 'Deadlock') !== false || strpos($errMsg, 'Serialization failure') !== false) {
                        $isDeadlock = true;
                    }
                }

                if ($isDeadlock && $i < $maxRetries - 1) {
                    Yii::warning("Deadlock detected, retrying transaction... (" . ($i + 1) . "/{$maxRetries})", __METHOD__);
                    usleep(mt_rand(100000, 300000));
                    continue;
                }
                
                Yii::error("SyncUpload Toplu İşlem Hatası: {$e->getMessage()}\nTrace: {$e->getTraceAsString()}", __METHOD__);
                Yii::$app->response->setStatusCode(500);
                return [
                    'success' => false,
                    'error' => 'Toplu senkronizasyon işlemi bir hata nedeniyle geri alındı.',
                    'details' => $e->getMessage()
                ];
            }
        }
        
        Yii::$app->response->setStatusCode(500);
        return [
            'success' => false,
            'error' => 'İşlem maksimum deneme sayısına ulaştıktan sonra bile başarısız oldu.',
        ];
    }

    private function _createGoodsReceipt($data, $db) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || empty($header['employee_id'])) {
            return ['status' => 'error', 'message' => 'Geçersiz veri: "header", "items" veya "employee_id" eksik.'];
        }

        $malKabulLocationId = 1;
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
                'receipt_id' => $receiptId,
                'urun_id' => $item['urun_id'],
                'quantity_received' => $item['quantity'],
                'pallet_barcode' => $item['pallet_barcode'] ?? null,
            ])->execute();
            $this->upsertStock($db, $item['urun_id'], $malKabulLocationId, $item['quantity'], $item['pallet_barcode'] ?? null, 'receiving');
        }

        if ($siparisId) {
            $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 2], ['id' => $siparisId])->execute();
        }

        return ['status' => 'success', 'receipt_id' => $receiptId];
    }

    private function _createInventoryTransfer($data, $db) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || !isset($header['employee_id'], $header['source_location_id'], $header['target_location_id'])) {
            return ['status' => 'error', 'message' => 'Geçersiz transfer verisi: Gerekli başlık bilgileri eksik.'];
        }

        $sourceLocationId = $header['source_location_id'];
        $operationType = $header['operation_type'] ?? 'box_transfer';
        $siparisId = $header['siparis_id'] ?? null;
        $isPutawayOperation = ($sourceLocationId == 1);

        foreach ($items as $item) {
            $productId = $item['product_id'];
            $quantity = (float)$item['quantity'];
            // DÜZELTME: Flutter tarafından 'pallet_id' olarak gönderiliyor.
            $sourcePallet = $item['pallet_id'] ?? null;
            $targetPallet = ($operationType === 'pallet_transfer') ? $sourcePallet : null;

            $this->upsertStock($db, $productId, $sourceLocationId, -$quantity, $sourcePallet, $isPutawayOperation ? 'receiving' : 'available');
            $this->upsertStock($db, $productId, $header['target_location_id'], $quantity, $targetPallet, 'available');

            $db->createCommand()->insert('inventory_transfers', [
                'urun_id' => $productId,
                'from_location_id' => $sourceLocationId,
                'to_location_id' => $header['target_location_id'],
                'quantity' => $quantity,
                'from_pallet_barcode' => $sourcePallet,
                'pallet_barcode' => $targetPallet,
                'employee_id' => $header['employee_id'],
                'transfer_date' => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
            ])->execute();

            if ($isPutawayOperation && $siparisId) {
                $db->createCommand(
                    "UPDATE satin_alma_siparis_fis_satir SET putaway_quantity = putaway_quantity + :qty WHERE siparis_id = :sid AND urun_id = :pid",
                    [':qty' => $quantity, ':sid' => $siparisId, ':pid' => $productId]
                )->execute();
            }
        }

        if ($isPutawayOperation && $siparisId) {
            $this->checkAndFinalizePoStatus($db, $siparisId);
        }

        return ['status' => 'success'];
    }

    // ANA DÜZELTME: Bu fonksiyon, hatalı forUpdate() metodunu kullanmayacak şekilde yeniden yazıldı.
    // Artık stok kilitleme işlemi için standart "SELECT ... FOR UPDATE" kullanılıyor.
    private function upsertStock($db, $urunId, $locationId, $qtyChange, $palletBarcode, $stockStatus) {

        $sql = "SELECT * FROM inventory_stock WHERE urun_id = :urun_id AND location_id = :location_id AND stock_status = :stock_status";
        $params = [':urun_id' => $urunId, ':location_id' => $locationId, ':stock_status' => $stockStatus];

        if ($palletBarcode === null) {
            $sql .= " AND pallet_barcode IS NULL";
        } else {
            $sql .= " AND pallet_barcode = :pallet_barcode";
            $params[':pallet_barcode'] = $palletBarcode;
        }
        $sql .= " FOR UPDATE"; // Kilitleme işlemi burada yapılır.

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
                'urun_id' => $urunId,
                'location_id' => $locationId,
                'quantity' => (float)$qtyChange,
                'pallet_barcode' => $palletBarcode,
                'stock_status' => $stockStatus
            ])->execute();
        } else {
            // Negatif bir değişiklik (stok düşüşü) isteniyor ama kaynakta stok bulunamadı.
            throw new \Exception("Stok düşme hatası: Kaynakta yeterli veya uygun statüde ürün bulunamadı. Ürün: $urunId, Lokasyon: $locationId, Palet: $palletBarcode, Statü: $stockStatus");
        }
    }

    private function checkAndFinalizePoStatus($db, $siparisId) {
        if (!$siparisId) return;

        $orderLines = (new Query())
            ->from('satin_alma_siparis_fis_satir')
            ->where(['siparis_id' => $siparisId])
            ->all($db);

        if (empty($orderLines)) return;

        $allLinesCompleted = true;
        foreach ($orderLines as $line) {
            $ordered = (float)$line['miktar'];
            $putaway = (float)$line['putaway_quantity'];
            if ($putaway < $ordered - 0.001) { // Tolerans payı eklendi
                $allLinesCompleted = false;
                break;
            }
        }

        if ($allLinesCompleted) {
            $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 3], ['id' => $siparisId])->execute();
        }
    }

    private function _forceCloseOrder($data, $db) {
        $siparisId = $data['siparis_id'] ?? null;
        if (empty($siparisId)) {
            return ['status' => 'error', 'message' => 'Geçersiz veri: "siparis_id" eksik.'];
        }

        $count = $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 4], ['id' => $siparisId])->execute();

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

            $data['employees'] = (new Query())->from('employees')->where(['is_active' => 1, 'warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['employees'], ['id', 'warehouse_id', 'is_active']);

            $poQuery = (new Query())->from('satin_alma_siparis_fis')->where(['lokasyon_id' => $warehouseId]);
            $data['satin_alma_siparis_fis'] = $poQuery->all();
            $this->castNumericValues($data['satin_alma_siparis_fis'], ['id', 'lokasyon_id', 'status', 'delivery', 'gun']);

            $poIds = array_column($data['satin_alma_siparis_fis'], 'id');
            if (!empty($poIds)) {
                $data['satin_alma_siparis_fis_satir'] = (new Query())->from('satin_alma_siparis_fis_satir')->where(['in', 'siparis_id', $poIds])->all();
                $this->castNumericValues($data['satin_alma_siparis_fis_satir'], ['id', 'siparis_id', 'urun_id', 'status'], ['miktar', 'putaway_quantity']);

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
            }

            $locationIds = array_column($data['warehouses_shelfs'], 'id');
            if (!empty($locationIds)) {
                $data['inventory_stock'] = (new Query())->from('inventory_stock')->where(['in', 'location_id', $locationIds])->all();
                 $this->castNumericValues($data['inventory_stock'], ['id', 'urun_id', 'location_id'], ['quantity']);
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