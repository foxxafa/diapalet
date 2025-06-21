<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;
use yii\web\Response;
use yii\db\Transaction;
use yii\db\Query;

class TerminalController extends Controller
{
    /**
     * Gelen isteklerin JSON formatında olacağını, CSRF kontrolünü devre dışı bırakacağımızı
     * ve API anahtarı kontrolünü yapacağımızı belirtiyoruz.
     */
    public function beforeAction($action)
    {
        Yii::$app->response->format = Response::FORMAT_JSON;
        $this->enableCsrfValidation = false;

        // Login action'ı hariç diğer tüm action'lar için API anahtarını kontrol et.
        // Health-check gibi public endpoint'ler de buraya eklenebilir.
        if ($action->id !== 'login' && $action->id !== 'health-check') {
            $this->checkApiKey();
        }

        return parent::beforeAction($action);
    }

    /**
     * İstek gövdesini JSON olarak okumak için yardımcı fonksiyon.
     */
    private function getJsonBody()
    {
        $rawBody = Yii::$app->request->getRawBody();
        $decoded = json_decode($rawBody, true);
        return is_array($decoded) ? $decoded : [];
    }

    /**
     * Gelen istekte geçerli bir 'Authorization: Bearer <token>' başlığı olup olmadığını kontrol eder.
     */
    private function checkApiKey()
    {
        $authHeader = Yii::$app->request->headers->get('Authorization');

        if ($authHeader === null || !preg_match('/^Bearer\s+(.+)$/', $authHeader, $matches)) {
            Yii::$app->response->statusCode = 401; // Unauthorized
            echo json_encode(['success' => false, 'error' => 'Yetkisiz erişim: API anahtarı eksik veya geçersiz.']);
            Yii::$app->end();
        }
    }

    // -----------------------------------------------------------------------------
    // ENDPOINT'LER
    // -----------------------------------------------------------------------------

    /**
     * Kullanıcı girişi için.
     */
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

    /**
     * Cihazdan sunucuya bekleyen işlemleri yüklemek için.
     */
    public function actionSyncUpload()
    {
        $payload = $this->getJsonBody();
        $operations = $payload['operations'] ?? [];
        $results = [];
        Yii::$app->response->statusCode = 200; // Varsayılan yanıt kodu

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
                    Yii::$app->response->statusCode = 400; // Hatalı istek
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


    /**
     * Sunucudan cihaza veri indirmek için.
     */
    public function actionSyncDownload()
    {
        $payload = $this->getJsonBody();
        $warehouseId = $payload['warehouse_id'] ?? null;

        if (!$warehouseId) {
            Yii::$app->response->statusCode = 400;
            return ['success' => false, 'error' => 'Depo ID (warehouse_id) zorunludur.'];
        }

        try {
            $data = [];
            $data['urunler'] = (new Query())->from('urunler')->all();
            $data['locations'] = (new Query())->from('warehouses_shelfs')->where(['warehouse_id' => $warehouseId])->all();
            $data['employees'] = (new Query())->from('employees')->where(['is_active' => 1, 'warehouse_id' => $warehouseId])->all();

            $poQuery = (new Query())->from('satin_alma_siparis_fis')->where(['lokasyon_id' => $warehouseId]);
            $data['satin_alma_siparis_fis'] = $poQuery->all();

            $poIds = array_column($data['satin_alma_siparis_fis'], 'id');
            if (!empty($poIds)) {
                $data['satin_alma_siparis_fis_satir'] = (new Query())->from('satin_alma_siparis_fis_satir')->where(['in', 'siparis_id', $poIds])->all();
                $receipts = (new Query())->from('goods_receipts')->where(['in', 'siparis_id', $poIds])->all();
                $data['goods_receipts'] = $receipts;

                $receiptIds = array_column($receipts, 'id');
                $data['goods_receipt_items'] = !empty($receiptIds) ? (new Query())->from('goods_receipt_items')->where(['in', 'receipt_id', $receiptIds])->all() : [];
            } else {
                $data['satin_alma_siparis_fis_satir'] = [];
                $data['goods_receipts'] = [];
                $data['goods_receipt_items'] = [];
            }

            $locationIds = array_column($data['locations'], 'id');
            if (!empty($locationIds)) {
                $data['inventory_stock'] = (new Query())->from('inventory_stock')->where(['in', 'location_id', $locationIds])->all();
                $data['inventory_transfers'] = (new Query())->from('inventory_transfers')->where(['or', ['in', 'from_location_id', $locationIds], ['in', 'to_location_id', $locationIds]])->all();
            } else {
                $data['inventory_stock'] = [];
                $data['inventory_transfers'] = [];
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

    /**
     * Sunucu sağlık durumunu kontrol etmek için public endpoint.
     */
    public function actionHealthCheck()
    {
        return ['status' => 'ok', 'message' => 'API Sunucusu çalışıyor.', 'timestamp' => date('c')];
    }

    // -----------------------------------------------------------------------------
    // İŞLEM YARDIMCI FONKSİYONLARI (HELPERS)
    // -----------------------------------------------------------------------------

    /**
     * GÜNCELLEME: Envanter transfer işlemini veritabanına kaydeder.
     */
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

                // Flutter uygulamasından gelen 'pallet_id' kaynak paleti temsil eder.
                $sourcePallet = $item['pallet_id'] ?? null;
                $targetPallet = null;

                if ($operationType === 'pallet_transfer') {
                    $targetPallet = $sourcePallet; // Tam palet transferinde kaynak ve hedef palet aynıdır.
                }

                // 1. Kaynak lokasyondaki stoğu azalt
                $this->upsertStock($db, $productId, $header['source_location_id'], -$quantity, $sourcePallet);

                // 2. Hedef lokasyondaki stoğu artır
                $this->upsertStock($db, $productId, $header['target_location_id'], $quantity, $targetPallet);

                // 3. Transfer işlemini logla
                $db->createCommand()->insert('inventory_transfers', [
                    'urun_id' => $productId,
                    'from_location_id' => $header['source_location_id'],
                    'to_location_id' => $header['target_location_id'],
                    'quantity' => $quantity,
                    'from_pallet_barcode' => $sourcePallet, // GÜNCELLEME: Kaynak palet kaydediliyor
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
            Yii::$app->response->statusCode = 201; // Created
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

        $orderedItems = (new Query())->select(['urun_id', 'miktar'])->from('satin_alma_siparis_fis_satir')->where(['siparis_id' => $siparisId])->all($db);
        if (empty($orderedItems)) return;

        $receivedTotalsList = (new Query())
            ->select(['gri.urun_id', 'total_received' => new \yii\db\Expression('SUM(gri.quantity_received)')])
            ->from(['gri' => 'goods_receipt_items'])
            ->innerJoin(['gr' => 'goods_receipts'], 'gr.id = gri.receipt_id')
            ->where(['gr.siparis_id' => $siparisId])->groupBy('gri.urun_id')->all($db);
        $receivedTotals = \yii\helpers\ArrayHelper::map($receivedTotalsList, 'urun_id', 'total_received');

        $allCompleted = true;
        $hasAnyReceipts = !empty($receivedTotals);

        foreach ($orderedItems as $item) {
            if ((float)($receivedTotals[$item['urun_id']] ?? 0) < (float)$item['miktar']) {
                $allCompleted = false;
                break;
            }
        }

        if ($allCompleted) {
            $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 3], ['id' => $siparisId])->execute(); // 3: Tamamlandı
        } elseif ($hasAnyReceipts) {
            $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 2], ['id' => $siparisId])->execute(); // 2: Kısmi Kabul
        }
    }
}