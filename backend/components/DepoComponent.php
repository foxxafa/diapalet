<?php
namespace app\components;

use Yii;
use yii\base\Component;
use app\components\Dia; // Dia bileşeninin doğru yerde olduğundan emin ol

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
            // Senin şemandaki doğru tablo adları: 'shelfs' ve 'warehouses'
            $db->createCommand('SET FOREIGN_KEY_CHECKS=0')->execute();
            $db->createCommand()->truncateTable('shelfs')->execute();
            $db->createCommand()->truncateTable('warehouses')->execute();
            // branches tablosunu da temizlemek iyi olabilir, çünkü depolar onlara bağlı.
            $db->createCommand()->truncateTable('branches')->execute();
            $db->createCommand('SET FOREIGN_KEY_CHECKS=1')->execute();

            // 2. Dia'dan şube ve depoları çek ve veritabanına kaydet (Güncellenmiş Fonksiyon)
            $warehousesResult = self::fetchAndSaveBranchesAndWarehouses();
            if ($warehousesResult['status'] === 'error') {
                throw new \Exception("AŞAMA 1 (Şube/Depo Çekme) BAŞARISIZ: " . $warehousesResult['message']);
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
            // Hata detayını daha anlaşılır yapalım
            return ['status' => 'error', 'message' => $e->getMessage(), 'trace' => $e->getTraceAsString()];
        }
    }

    /**
     * YENİ FONKSİYON: Dia'dan hem şubeleri hem de depoları çeker.
     * Bu, depoları doğru şube (branch) ile ilişkilendirmemizi sağlar.
     */
    private static function fetchAndSaveBranchesAndWarehouses() {
        // Dia'dan yetkili olunan tüm şube ve depoları çekelim.
        // Bu bize şube kodu (branch_code) ve depo kodu (warehouse_code) bilgilerini verir.
        $subeDepoListesi = Dia::subeDepolarGetir(); // dia.php içinde bu fonksiyonun olması lazım.

        if (empty($subeDepoListesi) || !isset($subeDepoListesi['result'])) {
            return ['status' => 'error', 'message' => 'Dia API yanıtında "result" anahtarı bulunamadı veya boş (subeDepolarGetir).', 'response' => $subeDepoListesi];
        }

        $db = Yii::$app->db;
        $branchCount = 0;
        $warehouseCount = 0;

        foreach ($subeDepoListesi['result'] as $yetki) {
            if (isset($yetki['subeler'])) {
                foreach ($yetki['subeler'] as $sube) {
                    // Şubeyi (Branch) veritabanına ekle
                    $db->createCommand()->insert('branches', [
                        'name' => $sube['aciklama'],
                        'branch_code' => $sube['subekodu'],
                        '_key' => $sube['_key']
                    ])->execute();
                    $branchId = $db->getLastInsertID();
                    $branchCount++;

                    // O şubeye ait depoları işle
                    if (isset($sube['depolar'])) {
                        foreach ($sube['depolar'] as $depo) {
                            $db->createCommand()->insert('warehouses', [
                                'name' => $depo['aciklama'],
                                'warehouse_code' => $depo['depokodu'],
                                'branch_id' => $branchId, // İşte sihrin gerçekleştiği yer!
                                'dia_id' => $depo['_key']
                            ])->execute();
                            $warehouseCount++;
                        }
                    }
                }
            }
        }
        return ['status' => 'success', 'message' => "$branchCount şube ve $warehouseCount depo eklendi."];
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

        $url = Yii::$app->params['dia_base_url'] . Yii::$app->params['dia_endpoints']['scf'];
        $requestBody = ["scf_rafyeri_listele" => [ "session_id" => $session_id, "firma_kodu" => 1, "limit" => 20000 ]];

        $response = self::makeRequest($url, $requestBody);
        if ($response['status'] === 'error') return $response;

        if (empty($response['data']['result'])) {
            return ['status' => 'success', 'message' => "0 raf eklendi (Raf listesi Dia'dan boş geldi)."];
        }

        $shelfsFromDia = $response['data']['result'];
        $db = Yii::$app->db;
        $count = 0;

        // Yerel veritabanındaki depoları Dia ID'lerine göre bir haritaya alalım
        $warehouseMap = $db->createCommand('SELECT dia_id, id FROM warehouses')->queryAll();
        $lookup = array_column($warehouseMap, 'id', 'dia_id');

        foreach ($shelfsFromDia as $shelf) {
            $dia_warehouse_key = $shelf['_key_sis_depo'];
            if (isset($lookup[$dia_warehouse_key])) {
                $local_warehouse_id = $lookup[$dia_warehouse_key];

                // Şemandaki doğru tablo ve sütun adlarını kullanıyoruz
                $db->createCommand()->insert('shelfs', [
                    'warehouse_id' => $local_warehouse_id,
                    'name' => $shelf['aciklama'] ?? 'İsimsiz Raf',
                    'code' => $shelf['kod'] ?? 'KODSUZ',
                    'dia_key' => $shelf['_key'], // Bu alanı da şemana göre ekledik
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