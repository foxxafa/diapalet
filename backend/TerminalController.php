<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;
use yii\web\Response;
use yii\db\Transaction;
use yii\db\Query;
use yii\helpers\ArrayHelper;
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
        $results = [];

        foreach ($operations as $op) {
            $opType = $op['type'] ?? null;
            $opData = $op['data'] ?? [];
            $result = ['status' => 'error', 'message' => 'Unknown operation']; // Default error
            try {
                if ($opType === 'goodsReceipt') {
                    $result = $this->_createGoodsReceipt($opData);
                } elseif ($opType === 'inventoryTransfer') {
                    $result = $this->_createInventoryTransfer($opData);
                } elseif ($opType === 'forceCloseOrder') {
                    $result = $this->_forceCloseOrder($opData);
                } else {
                    Yii::$app->response->statusCode = 400;
                    $result['message'] = "Bilinmeyen operasyon tipi: {$opType}";
                }
            } catch (\Exception $e) {
                Yii::error("SyncUpload Hatası ({$opType}): {$e->getMessage()}\nTrace: {$e->getTraceAsString()}", __METHOD__);
                Yii::$app->response->statusCode = 500;
                $result['message'] = $e->getMessage();
            }
            $results[] = ['operation_type' => $opType, 'result' => $result];
        }
        return ['success' => true, 'results' => $results];
    }

    private function _createGoodsReceipt($data) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || empty($header['employee_id'])) {
            throw new \yii\web\BadRequestHttpException('Geçersiz veri: "header", "items" veya "employee_id" eksik.');
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

                // YENİ MANTIK: Gelen stoğu her zaman 'receiving' olarak ekle.
                $this->upsertStock($db, $item['urun_id'], $malKabulLocationId, $item['quantity'], $item['pallet_barcode'] ?? null, 'receiving');
            }

            if ($siparisId) {
                // Siparişin durumunu 2 (Kısmi Kabul) yap. Tamamlandı kontrolü sadece yerleştirmede olacak.
                $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 2], ['id' => $siparisId])->execute();
                Yii::info("Sipariş #$siparisId durumu 2 (Kısmi Kabul) olarak güncellendi.", __METHOD__);
            }

            $transaction->commit();
            return ['status' => 'success', 'receipt_id' => $receiptId];

        } catch (\Exception $e) {
            $transaction->rollBack();
            Yii::error("Mal Kabul DB Hatası: {$e->getMessage()}", __METHOD__);
            throw new \yii\web\ServerErrorHttpException('Veritabanı hatası: Mal kabul kaydedilemedi.');
        }
    }

    private function _createInventoryTransfer($data) {
        $header = $data['header'] ?? [];
        $items = $data['items'] ?? [];
        if (empty($header) || empty($items) || !isset($header['employee_id'], $header['source_location_id'], $header['target_location_id'])) {
            throw new \yii\web\BadRequestHttpException('Geçersiz transfer verisi: Gerekli başlık bilgileri eksik.');
        }

        $db = Yii::$app->db;
        $transaction = $db->beginTransaction(Transaction::SERIALIZABLE);

        $sourceLocationId = $header['source_location_id'];
        $operationType = $header['operation_type'] ?? 'box_transfer'; // Varsayılan değer güncellendi.
        $siparisId = $header['siparis_id'] ?? null;           // Yerleştirme mantığı için sipariş ID'si

        try {
            // Transfer, mal kabul alanından yapılıyorsa bu bir 'yerleştirme' işlemidir.
            $isPutawayOperation = ($sourceLocationId == 1); // 1 = Mal Kabul Alanı ID'si (varsayım)

            foreach ($items as $item) {
                $productId = $item['product_id'];
                $quantity = (float)$item['quantity'];
                $sourcePallet = $item['pallet_id'] ?? null;

                // 1. Hedefteki palet durumunu operasyon tipine göre belirle
                $targetPallet = null; // Varsayılan: serbest stok (paletsiz)

                // ############ ANA HATA DÜZELTMESİ ############
                // Gelen 'operation_type' değeri 'pallet_transfer' olmalı.
                if ($operationType === 'pallet_transfer') {
                    $targetPallet = $sourcePallet; // Tam palet transferinde palet ID korunur
                }
                // 'boxFromPallet' ve 'box_transfer' modlarında $targetPallet null kalır, bu da ürünün serbest stok olmasını sağlar.
                // ############ DÜZELTME SONU ############

                // 2. Kaynak stoktan miktarı düş
                $this->upsertStock($db, $productId, $sourceLocationId, -$quantity, $sourcePallet, $isPutawayOperation ? 'receiving' : 'available');

                // 3. Hedef stoka miktarı ekle
                $this->upsertStock($db, $productId, $header['target_location_id'], $quantity, $targetPallet, 'available');

                // 4. Transfer işlemini logla
                $db->createCommand()->insert('inventory_transfers', [
                    'urun_id' => $productId,
                    'from_location_id' => $sourceLocationId,
                    'to_location_id' => $header['target_location_id'],
                    'quantity' => $quantity,
                    'from_pallet_barcode' => $sourcePallet,
                    'pallet_barcode' => $targetPallet, // Hedef palet durumunu doğru şekilde kaydet
                    'employee_id' => $header['employee_id'],
                    'transfer_date' => $header['transfer_date'] ?? new \yii\db\Expression('NOW()'),
                ])->execute();

                // 5. Eğer bu bir yerleştirme işlemiyse, siparişteki yerleştirilen miktarı güncelle
                if ($isPutawayOperation && $siparisId) {
                    $db->createCommand(
                        "UPDATE satin_alma_siparis_fis_satir SET putaway_quantity = putaway_quantity + :qty WHERE siparis_id = :sid AND urun_id = :pid",
                        [':qty' => $quantity, ':sid' => $siparisId, ':pid' => $productId]
                    )->execute();
                }
            }

            // 6. Transferden sonra, eğer bir yerleştirme işlemiyse, siparişin durumunu kontrol et ve gerekirse tamamla
            if ($isPutawayOperation && $siparisId) {
                $this->checkAndFinalizePoStatus($db, $siparisId);
            }

            $transaction->commit();
            return ['status' => 'success'];
        } catch (\Exception $e) {
            $transaction->rollBack();
            Yii::error("Envanter Transfer DB Hatası: {$e->getMessage()}", __METHOD__);
            throw new \yii\web\ServerErrorHttpException('Veritabanı hatası: Transfer kaydedilemedi.');
        }
    }

    // GÜNCELLENEN FONKSİYON: Stok durumunu da yönetir.
    private function upsertStock($db, $urunId, $locationId, $qtyChange, $palletBarcode, $stockStatus) {
        $condition = ['urun_id' => $urunId, 'location_id' => $locationId, 'stock_status' => $stockStatus];
        if ($palletBarcode === null) {
            $condition['pallet_barcode'] = null;
        } else {
            $condition['pallet_barcode'] = $palletBarcode;
        }

        $stock = (new Query())->from('inventory_stock')->where($condition)->one($db);

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
            Yii::warning("Negatif envanter engellendi veya düşülecek stok bulunamadı: urun_id: $urunId, location_id: $locationId, status: $stockStatus", __METHOD__);
            // Hata fırlatmak işlemi durdurur, bu önemlidir.
            throw new \Exception("Stok düşme hatası: Kaynakta yeterli veya uygun statüde ürün bulunamadı.");
        }
    }

    // YENİ FONKSİYON: Siparişin tüm satırlarının yerleştirilip yerleştirilmediğini kontrol eder.
    private function checkAndFinalizePoStatus($db, $siparisId) {
        if (!$siparisId) return;

        Yii::info("Sipariş tamamlama kontrolü başlatıldı: siparis_id: $siparisId", __METHOD__);

        $orderLines = (new Query())
            ->from('satin_alma_siparis_fis_satir')
            ->where(['siparis_id' => $siparisId])
            ->all($db);

        $allLinesCompleted = true;
        if (empty($orderLines)) {
             $allLinesCompleted = false; // Siparişin satırı yoksa tamamlanmış sayılmaz.
        }

        foreach ($orderLines as $line) {
            $ordered = (float)$line['miktar'];
            $putaway = (float)$line['putaway_quantity'];

            // Yerleştirilen miktar, sipariş edilen miktardan büyük veya eşit mi?
            if ($putaway < $ordered) {
                $allLinesCompleted = false;
                Yii::info("Sipariş #$siparisId, Satır #{$line['id']} henüz tamamlanmamış (Sipariş: $ordered, Yerleştirilen: $putaway).", __METHOD__);
                break; // Bir tane bile eksik varsa döngüden çık.
            }
        }

        if ($allLinesCompleted) {
            Yii::info("Siparişin #$siparisId tüm satırları tamamlandı. Durum 3 (Tamamlandı) olarak güncelleniyor.", __METHOD__);
            $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 3], ['id' => $siparisId])->execute();
        } else {
            Yii::info("Sipariş #$siparisId henüz tamamlanmadı. Durum 2 (Kısmi Kabul) olarak kalacak.", __METHOD__);
        }
    }

    // YENİ FONKSİYON: Bir siparişi manuel olarak tamamlandı (statü 4) olarak işaretler.
    private function _forceCloseOrder($data) {
        $siparisId = $data['siparis_id'] ?? null;
        if (empty($siparisId)) {
            throw new \yii\web\BadRequestHttpException('Geçersiz veri: "siparis_id" eksik.');
        }

        $db = Yii::$app->db;
        $count = $db->createCommand()->update('satin_alma_siparis_fis', ['status' => 4], ['id' => $siparisId])->execute();

        if ($count > 0) {
            Yii::info("Sipariş #$siparisId manuel olarak kapatıldı (Statü 4).", __METHOD__);
            return ['status' => 'success', 'message' => "Order #$siparisId closed."];
        } else {
            Yii::warning("Kapatılacak sipariş bulunamadı: #$siparisId", __METHOD__);
            return ['status' => 'not_found', 'message' => "Order #$siparisId not found."];
        }
    }

    // --- Diğer End-point'ler (Değişiklik Gerekmiyor) ---

    public function actionSyncDownload()
    {
        // ... (Bu fonksiyonda değişiklik yapmaya gerek yok, ancak yeni eklenen alanları göndermesi faydalı olur)
        $payload = $this->getJsonBody();
        $warehouseId = $payload['warehouse_id'] ?? null;

        if (!$warehouseId) {
            Yii::$app->response->statusCode = 400;
            return ['success' => false, 'error' => 'Depo ID (warehouse_id) zorunludur.'];
        }
        $warehouseId = (int)$warehouseId;

        try {
            $data = [];
            // Urunler
            $urunlerData = (new Query())->select(['id' => 'UrunId', 'StokKodu', 'UrunAdi', 'Barcode1', 'aktif'])->from('urunler')->all();
            $this->castNumericValues($urunlerData, ['id', 'aktif']);
            $data['urunler'] = $urunlerData;

            // Raflar
            $data['warehouses_shelfs'] = (new Query())->from('warehouses_shelfs')->where(['warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['warehouses_shelfs'], ['id', 'warehouse_id', 'is_active']);

            // Çalışanlar
            $data['employees'] = (new Query())->from('employees')->where(['is_active' => 1, 'warehouse_id' => $warehouseId])->all();
            $this->castNumericValues($data['employees'], ['id', 'warehouse_id', 'is_active']);

            // Siparişler ve bağlı tablolar
            $poQuery = (new Query())->from('satin_alma_siparis_fis')->where(['lokasyon_id' => $warehouseId]);
            $data['satin_alma_siparis_fis'] = $poQuery->all();
            $this->castNumericValues($data['satin_alma_siparis_fis'], ['id', 'lokasyon_id', 'status', 'delivery', 'gun']);

            $poIds = array_column($data['satin_alma_siparis_fis'], 'id');
            if (!empty($poIds)) {
                // GÜNCELLEME: yerlestirilen_miktar alanını da gönder
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

            // GÜNCELLEME: stock_status alanını da gönder
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