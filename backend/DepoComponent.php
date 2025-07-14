<?php
namespace app\components;

use Yii;
use yii\base\Component;
use app\components\Dia;

class DepoComponent extends Component
{
    /**
     * Ana senkronizasyon fonksiyonu. Tüm depo ve raf verilerini Dia'dan çeker.
     * Bu fonksiyon, önce yerel tabloları temizler, sonra depoları, en son da rafları ekler.
     */
    public static function syncWarehousesAndShelfs()
    {
        $db = Yii::$app->db;
        $transaction = $db->beginTransaction();

        try {
            // 1. Önce tabloları güvenli bir şekilde boşalt
            $db->createCommand('SET FOREIGN_KEY_CHECKS=0')->execute();
            $db->createCommand()->truncateTable('shelfs')->execute();
            $db->createCommand()->truncateTable('warehouses')->execute();
            $db->createCommand('SET FOREIGN_KEY_CHECKS=1')->execute();

            // 2. Dia'dan depoları çek ve veritabanına kaydet
            $warehousesResult = self::fetchAndSaveWarehouses();
            if ($warehousesResult['status'] === 'error') {
                throw new \Exception("AŞAMA 1 (Depo Çekme) BAŞARISIZ: " . $warehousesResult['message']);
            }

            // 3. Dia'dan rafları çek ve doğru depoyla ilişkilendirerek kaydet
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
            return ['status' => 'error', 'message' => $e->getMessage()];
        }
    }

    /**
     * Dia'dan 'scf_rafyeri_takipli_depo_listele' servisini kullanarak depo listesini çeker.
     * Gelen veriyi (array içinde array) doğru şekilde işler ve 'warehouses' tablosuna kaydeder.
     */
    private static function fetchAndSaveWarehouses() {
        $session_id = Dia::getsessionid();
        if (!$session_id) {
             return ['status' => 'error', 'message' => 'Dia oturum kimliği alınamadı (Depo).'];
        }

        $url = "https://aytacfoods.ws.dia.com.tr/api/v3/scf/json";
        $requestBody = ["scf_rafyeri_takipli_depo_listele" => [ "session_id" => $session_id, "firma_kodu" => 1 ]];

        $response = self::makeRequest($url, $requestBody);
        if ($response['status'] === 'error') return $response;

        $warehousesFromDia = $response['data']['result'];
        $db = Yii::$app->db;
        $count = 0;

        foreach ($warehousesFromDia as $warehouse) {
            $diaId = $warehouse[0];
            $warehouseName = $warehouse[1];
            $warehouseCode = 'DEPO-' . $diaId; // Benzersiz bir kod oluşturuyoruz

            $db->createCommand()->insert('warehouses', [
                'name' => $warehouseName,
                'warehouse_code' => $warehouseCode,
                'dia_id' => $diaId,
            ])->execute();
            $count++;
        }
        return ['status' => 'success', 'message' => "$count depo eklendi."];
    }

    /**
     * Dia'dan 'scf_rafyeri_listele' servisini kullanarak tüm rafları çeker.
     * Daha önce kaydedilen depolarla eşleştirerek 'shelfs' tablosuna kaydeder.
     */
    private static function fetchAndSaveShelfs() {
        $session_id = Dia::getsessionid();
        if (!$session_id) {
             return ['status' => 'error', 'message' => 'Dia oturum kimliği alınamadı (Raf).'];
        }

        $url = "https://aytacfoods.ws.dia.com.tr/api/v3/scf/json";
        $requestBody = ["scf_rafyeri_listele" => [ "session_id" => $session_id, "firma_kodu" => 1, "limit" => 20000 ]]; // Yüksek limit

        $response = self::makeRequest($url, $requestBody);
        if ($response['status'] === 'error') return $response;

        if (empty($response['data']['result'])) {
            return ['status' => 'success', 'message' => "0 raf eklendi (Raf listesi Dia'dan boş geldi)."];
        }

        $shelfsFromDia = $response['data']['result'];
        $db = Yii::$app->db;
        $count = 0;

        $warehouseMap = $db->createCommand('SELECT dia_id, id FROM warehouses')->queryAll();
        $lookup = array_column($warehouseMap, 'id', 'dia_id');

        foreach ($shelfsFromDia as $shelf) {
            $dia_warehouse_key = $shelf['_key_sis_depo'];
            if (isset($lookup[$dia_warehouse_key])) {
                $local_warehouse_id = $lookup[$dia_warehouse_key];
                $db->createCommand()->insert('shelfs', [
                    'warehouse_id' => $local_warehouse_id,
                    'name' => $shelf['aciklama'] ?? 'İsimsiz Raf',
                    'code' => $shelf['kod'] ?? 'KODSUZ',
                    'is_active' => ($shelf['durum'] === 'A') ? 1 : 0,
                ])->execute();
                $count++;
            }
        }
        return ['status' => 'success', 'message' => "$count raf eklendi."];
    }

    /**
     * Dia'ya API isteği gönderen ve gelen yanıtı kontrol eden yardımcı fonksiyon.
     */
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
