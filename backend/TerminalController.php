<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;
use yii\web\Response;
use yii\db\Transaction;
use yii\db\Query;
use yii\helpers\ArrayHelper;
use app\components\DepoComponent; // <-- YENİ EKLENEN SATIR

class TerminalController extends Controller
{
    public function beforeAction($action)
    {
        Yii::$app->response->format = Response::FORMAT_JSON;
        $this->enableCsrfValidation = false;

        // 'sync-shelfs' action'ı için API Key kontrolünü atlıyoruz ki tarayıcıdan kolayca çalıştıralım.
        if ($action->id !== 'login' && $action->id !== 'health-check' && $action->id !== 'sync-shelfs') { // <-- GÜNCELLENEN SATIR
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
                if (isset($row[$key])) {
                    $row[$key] = (int)$row[$key];
                }
            }
            foreach ($floatKeys as $key) {
                if (isset($row[$key])) {
                    $row[$key] = (float)$row[$key];
                }
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
        $results = [];
        Yii::$app->response->statusCode = 200;

        foreach ($operations as $op) {
            $opType = $op['type'] ?? null;
            $opData = $op['data'] ?? [];
            try {
                if ($opType === 'goodsReceipt') {
                    $result = $this->_createGoodsReceipt($opData);
                } elseif ($opType === 'inventoryTransfer') {
                    $result = $this->_createInventoryTransfer($opData);
                } else {
                    $result = ['error' => "Bilinmeyen operasyon tipi: {$opType}"];
                    Yii::$app->response->statusCode = 400;
                }
                $results[] = ['operation' => $op, 'result' => $result];
            } catch (\Exception $e) {
                Yii::error("SyncUpload Hatası ({$opType}): {$e->getMessage()}", __METHOD__);
                $results[] = ['operation' => $op, 'result' => ['error' => $e->getMessage()]];
                Yii::$app->response->statusCode = 500;
            }
        }
        return ['success' => true, 'results' => $results];
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
                $this->castNumericValues($data['satin_alma_siparis_fis_satir'], ['id', 'siparis_id', 'urun_id', 'status'], ['miktar']);

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
        return ['status' => 'ok', 'message' => 'API Sunucusu çalışıyor.', 'timestamp' => date('c')];
    }

    private function _createInventoryTransfer($data) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];

        if (empty($header) || empty($items) || !isset($header['employee_id'], $header['source_location_id'], $header['target_location_id'])) {
            Yii::$app->response->statusCode = 400;
            return ['error' => 'Geçersiz transfer verisi: "header", "items" veya gerekli ID\'ler eksik.'];
        }

        $db = Yii::$app->db;
        $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);

        try {
            $operationType = $header['operation_type'] ?? 'box_transfer';

            foreach ($items as $item) {
                $productId = $item['product_id'];
                $quantity = (float)$item['quantity'];
                $sourcePallet = $item['pallet_id'] ?? null;

                $targetPallet = null;
                if ($operationType === 'pallet_transfer') {
                    $targetPallet = $sourcePallet;
                }

                $this->upsertStock($db, $productId, $header['source_location_id'], -$quantity, $sourcePallet);
                $this->upsertStock($db, $productId, $header['target_location_id'], $quantity, $targetPallet);

                $db->createCommand()->insert('inventory_transfers', [
                    'urun_id' => $productId,
                    'from_location_id' => $header['source_location_id'],
                    'to_location_id' => $header['target_location_id'],
                    'quantity' => $quantity,
                    'from_pallet_barcode' => $sourcePallet,
                    'pallet_barcode' => $targetPallet,
                    'employee_id' => $header['employee_id'],
                    'transfer_date' => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
                    'created_at' => new \yii\db\Expression('NOW()'),
                ])->execute();
            }

            $transaction->commit();
            return ['status' => 'success'];

        } catch (\Exception $e) {
            $transaction->rollBack();
            Yii::error("Envanter Transfer DB Hatası: {$e->getMessage()}", __METHOD__);
            Yii::$app->response->statusCode = 500;
            return ['error' => 'Veritabanı hatası: ' . $e->getMessage()];
        }
    }

    private function _createGoodsReceipt($data) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || empty($header['employee_id'])) {
            Yii::$app->response->statusCode = 400;
            return ['error' => 'Geçersiz veri: "header", "items" veya "employee_id" eksik.'];
        }

        $malKabulLocationId = 1;
        $siparisId = $header['siparis_id'] ?? null;
        $db = Yii::$app->db;
        $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);

        try {
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
                $this->upsertStock($db, $item['urun_id'], $malKabulLocationId, $item['quantity'], $item['pallet_barcode'] ?? null);
            }

            if ($siparisId) {
                $this->checkAndUpdatePoStatus($db, $siparisId);
            }

            $transaction->commit();
            Yii::$app->response->statusCode = 201;
            return ['receipt_id' => $receiptId, 'status' => 'success'];

        } catch (\Exception $e) {
            $transaction->rollBack();
            Yii::error("Mal Kabul DB Hatası: {$e->getMessage()}", __METHOD__);
            Yii::$app->response->statusCode = 500;
            return ['error' => 'Veritabanı hatası: ' . $e->getMessage()];
        }
    }

    private function upsertStock($db, $urunId, $locationId, $qtyChange, $palletBarcode) {
        $condition = ['urun_id' => $urunId, 'location_id' => $locationId];

        if ($palletBarcode === null) {
            $condition['pallet_barcode'] = null;
        } else {
            $condition['pallet_barcode'] = $palletBarcode;
        }

        $stock = (new Query())->select(['id', 'quantity'])->from('inventory_stock')->where($condition)->one($db);
        $qtyChangeDecimal = (float) $qtyChange;

        if ($stock) {
            $newQty = (float)($stock['quantity'] ?? 0.0) + $qtyChangeDecimal;
            if ($newQty > 0.001) {
                $db->createCommand()->update('inventory_stock', ['quantity' => $newQty], ['id' => $stock['id']])->execute();
            } else {
                $db->createCommand()->delete('inventory_stock', ['id' => $stock['id']])->execute();
            }
        } elseif ($qtyChangeDecimal > 0) {
            $db->createCommand()->insert('inventory_stock', [
                'urun_id' => $urunId, 'location_id' => $locationId,
                'quantity' => $qtyChangeDecimal, 'pallet_barcode' => $palletBarcode,
            ])->execute();
        } else {
            $warning = "Negatif envanter engellendi: Lokasyon #$locationId, Ürün #$urunId, Palet: " . ($palletBarcode ?? 'YOK');
            Yii::warning($warning, __METHOD__);
        }
    }

    private function checkAndUpdatePoStatus($db, $siparisId) {
        if (!$siparisId) return;

        Yii::info("Sipariş durumu kontrolü başlatıldı: siparis_id: $siparisId", __METHOD__);

        $currentStatus = (new Query())
            ->select('status')
            ->from('satin_alma_siparis_fis')
            ->where(['id' => $siparisId])
            ->scalar($db);

        if ($currentStatus != 1) {
            Yii::info("Sipariş durumu zaten $currentStatus. Güncelleme atlanıyor: siparis_id: $siparisId", __METHOD__);
            return;
        }

        Yii::info("Durum 2 (Kısmi Kabul) olarak güncelleniyor: siparis_id: $siparisId", __METHOD__);
        $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 2], ['id' => $siparisId])->execute();
    }

    // =================================================================
    // VVVVVV YENİ EKLENEN OTOMATİK SENKRONİZASYON FONKSİYONU VVVVVV
    // =================================================================
    public function actionSyncShelfs()
    {
        $result = DepoComponent::syncWarehousesAndShelfs();

        if ($result['status'] === 'error') {
            Yii::$app->response->statusCode = 500;
        }

        return $this->asJson($result);
    }
}