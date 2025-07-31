<?php
namespace app\components;

use Yii;
use yii\base\Component;
use app\components\Dia;

class DepoComponent extends Component
{
    public static function syncWarehousesAndShelfs()
    {
        $db = Yii::$app->db;
        $transaction = $db->beginTransaction();

        try {
            // DEĞİŞİKLİK: Artık tabloları tamamen silmiyoruz.
            // Sadece rafları temizleyebiliriz çünkü onlar tamamen depolara bağlı.
            $db->createCommand('SET FOREIGN_KEY_CHECKS=0')->execute();
            $db->createCommand()->truncateTable('shelfs')->execute();
            // $db->createCommand()->truncateTable('warehouses')->execute(); // BU SATIR SİLİNDİ
            // $db->createCommand()->truncateTable('branches')->execute(); // BU SATIR SİLİNDİ
            $db->createCommand('SET FOREIGN_KEY_CHECKS=1')->execute();

            // Dia'dan gelen verilerle mevcut şube ve depoları güncelle/ekle
            $warehousesResult = self::upsertBranchesAndWarehouses();
            if ($warehousesResult['status'] === 'error') {
                throw new \Exception("AŞAMA 1 (Şube/Depo Güncelleme) BAŞARISIZ: " . $warehousesResult['message']);
            }

            // Rafları çekip ekle (rafları her seferinde yeniden oluşturmak daha güvenli)
            $shelfsResult = self::fetchAndSaveShelfs();
            if ($shelfsResult['status'] === 'error') {
                throw new \Exception("AŞAMA 2 (Raf Çekme) BAŞARISIZ: " . $shelfsResult['message']);
            }

            $transaction->commit();
            return [
                'status' => 'success',
                'message' => $warehousesResult['message'] . ' ' . $shelfsResult['message']
            ];

        } catch (\Exception $e) {
            $transaction->rollBack();
            return ['status' => 'error', 'message' => $e->getMessage(), 'trace' => $e->getTraceAsString()];
        }
    }

    /**
     * YENİ AKILLI FONKSİYON: Mevcut kayıtları güncelle, yeni olanları ekle (Upsert).
     */
    private static function upsertBranchesAndWarehouses() {
        $subeDepoListesi = Dia::subeDepolarGetir();

        if (empty($subeDepoListesi) || !isset($subeDepoListesi['result'])) {
            return ['status' => 'error', 'message' => 'Dia API yanıtında "result" anahtarı bulunamadı veya boş (subeDepolarGetir).', 'response' => $subeDepoListesi];
        }

        $db = Yii::$app->db;
        $branchCreated = 0;
        $branchUpdated = 0;
        $warehouseCreated = 0;
        $warehouseUpdated = 0;

        foreach ($subeDepoListesi['result'] as $yetki) {
            if (isset($yetki['subeler'])) {
                foreach ($yetki['subeler'] as $sube) {
                    // Şube veritabanında var mı diye kontrol et
                    $existingBranch = (new Query())->select('id')->from('branches')->where(['branch_code' => $sube['subekodu']])->one();

                    if ($existingBranch) {
                        // Varsa güncelle
                        $db->createCommand()->update('branches', ['name' => $sube['aciklama'], '_key' => $sube['_key']], ['id' => $existingBranch['id']])->execute();
                        $branchId = $existingBranch['id'];
                        $branchUpdated++;
                    } else {
                        // Yoksa yeni ekle
                        $db->createCommand()->insert('branches', ['name' => $sube['aciklama'], 'branch_code' => $sube['subekodu'], '_key' => $sube['_key']])->execute();
                        $branchId = $db->getLastInsertID();
                        $branchCreated++;
                    }

                    if (isset($sube['depolar'])) {
                        foreach ($sube['depolar'] as $depo) {
                            // Depo veritabanında var mı diye kontrol et
                            $existingWarehouse = (new Query())->select('id')->from('warehouses')->where(['warehouse_code' => $depo['depokodu']])->one();

                            $warehouseData = [
                                'name' => $depo['aciklama'],
                                'warehouse_code' => $depo['depokodu'],
                                'branch_id' => $branchId, // En önemli alan
                                'dia_id' => $depo['_key']  // En önemli alan
                            ];

                            if ($existingWarehouse) {
                                // Varsa güncelle
                                $db->createCommand()->update('warehouses', $warehouseData, ['id' => $existingWarehouse['id']])->execute();
                                $warehouseUpdated++;
                            } else {
                                // Yoksa yeni ekle
                                $db->createCommand()->insert('warehouses', $warehouseData)->execute();
                                $warehouseCreated++;
                            }
                        }
                    }
                }
            }
        }
        return ['status' => 'success', 'message' => "$branchCreated şube eklendi, $branchUpdated güncellendi. $warehouseCreated depo eklendi, $warehouseUpdated güncellendi."];
    }

    /**
     * Bu fonksiyon rafları sıfırdan eklediği için aynı kalabilir.
     */
    private static function fetchAndSaveShelfs() {
        $session_id = Dia::getsessionid();
        if (!$session_id) {
             return ['status' => 'error', 'message' => 'Dia oturum kimliği alınamadı (Raf).'];
        }

        $url = (Yii::$app->params['dia_base_url'] ?? '') . (Yii::$app->params['dia_endpoints']['scf'] ?? '');
        $requestBody = ["scf_rafyeri_listele" => [ "session_id" => $session_id, "firma_kodu" => 1, "limit" => 20000 ]];

        $response = self::makeRequest($url, $requestBody);
        if ($response['status'] === 'error') return $response;

        if (empty($response['data']['result'])) {
            return ['status' => 'success', 'message' => "0 raf eklendi (Raf listesi Dia'dan boş geldi)."];
        }

        $shelfsFromDia = $response['data']['result'];
        $db = Yii::$app->db;
        $count = 0;

        $warehouseMap = (new Query())->select(['id', 'dia_id'])->from('warehouses')->all();
        $lookup = array_column($warehouseMap, 'id', 'dia_id');

        foreach ($shelfsFromDia as $shelf) {
            $dia_warehouse_key = $shelf['_key_sis_depo'];
            if (isset($lookup[$dia_warehouse_key])) {
                $local_warehouse_id = $lookup[$dia_warehouse_key];

                $db->createCommand()->insert('shelfs', [
                    'warehouse_id' => $local_warehouse_id,
                    'name' => $shelf['aciklama'] ?? 'İsimsiz Raf',
                    'code' => $shelf['kod'] ?? 'KODSUZ',
                    'dia_key' => $shelf['_key'],
                    'is_active' => ($shelf['durum'] === 'A') ? 1 : 0,
                ])->execute();
                $count++;
            }
        }
        return ['status' => 'success', 'message' => "$count raf eklendi."];
    }

    private static function makeRequest($url, $requestBody) {
        $jsonData = json_encode($requestBody);
        $curl = curl_init($url);
        curl_setopt_array($curl, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $jsonData,
            CURLOPT_HTTPHEADER => ['Content-Type: application/json', 'Content-Length: ' . strlen($jsonData)],
            CURLOPT_SSL_VERIFYPEER => false
        ]);
        $response = curl_exec($curl);
        $curlError = curl_error($curl);
        curl_close($curl);

        if ($curlError) {
             return ['status' => 'error', 'message' => 'cURL Hatası: ' . $curlError];
        }

        $responseData = json_decode($response, true);
        if (empty($responseData) || !isset($responseData['code']) || $responseData['code'] != '200') {
            return ['status' => 'error', 'message' => 'Dia API hatası veya geçersiz yanıt.', 'response' => $responseData];
        }
        if (!isset($responseData['result'])){
             return ['status' => 'error', 'message' => 'Dia API yanıtında "result" anahtarı bulunamadı.', 'response' => $responseData];
        }

        return ['status' => 'success', 'data' => $responseData];
    }
}