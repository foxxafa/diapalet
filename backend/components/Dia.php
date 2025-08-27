<?php 
namespace app\components;
use Yii;
use yii\base\Component;
use yii\base\InvalidConfigException;
use app\models\Satisfisleri;
use app\models\Satissatirlari; 
use app\models\Iadesatirlari; 
use app\models\CashRegisters;
use app\models\CariHareketler;
use app\models\Musteriler;
use app\models\Urunler;
use app\models\Satiscilar;
use app\models\SatinAlmaSiparisFisSatir;
use app\models\Branches;
use app\models\Warehouses;
use app\components\PythonDictConverter;
class Dia extends Component{
    private static function getDiaUrl($endpoint) {
        $baseUrl = Yii::$app->params['dia_base_url'];
        $endpoints = Yii::$app->params['dia_endpoints'];
        $url = $baseUrl . $endpoints[$endpoint];
        
        // Log ekle
        $logMessage = "=== getDiaUrl ===\n";
        $logMessage .= "Tarih: " . date('Y-m-d H:i:s') . "\n";
        $logMessage .= "Endpoint: " . $endpoint . "\n";
        $logMessage .= "Base URL: " . $baseUrl . "\n";
        $logMessage .= "Final URL: " . $url . "\n\n";
        //file_put_contents(\Yii::getAlias('@runtime/dia_url_log.txt'), $logMessage, FILE_APPEND | LOCK_EX);
        
        return $url;
    }

    public static function getsessionid(){
        $logMessage = "=== getsessionid BAŞLADI ===\n";
        $logMessage .= "Tarih: " . date('Y-m-d H:i:s') . "\n";
        
        $url =  self::getDiaUrl('sis');
        $logMessage .= "Login URL: " . $url . "\n";
    
        // SESSION ID MANUEL GİRİLMELİ
        $session_id = "";
        $firma_kodu = 1;
        $donem_kodu = 1;
        $username = Yii::$app->params['dia_user'];
        $password = Yii::$app->params['dia_pass'];
        $apikey = Yii::$app->params['dia_key'];
        
        $logMessage .= "Username: " . $username . "\n";
        $logMessage .= "API Key: " . $apikey . "\n";
        
        $data = <<<EOT
        {"login" :
            {"username": "$username",
             "password": "$password",
             "disconnect_same_user": "true",
             "lang": "tr", 
             "params": {"apikey": "$apikey"}
            }
        }
        
        EOT;
        
        $logMessage .= "Login Data: " . $data . "\n";
        
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_POSTFIELDS, $data);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_HTTPHEADER, array(
            'Content-Type: application/json',
            'Content-Length: ' . strlen($data))
        );
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_TIMEOUT, 30);
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 10);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        
        $logMessage .= "cURL seçenekleri ayarlandı\n";
        
        $result = curl_exec($curl);
        $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
        $curlError = curl_error($curl);
        $curlErrno = curl_errno($curl);
        
        $logMessage .= "cURL HTTP Code: " . $httpCode . "\n";
        $logMessage .= "cURL Error No: " . $curlErrno . "\n";
        $logMessage .= "cURL Error: " . $curlError . "\n";
        $logMessage .= "cURL Response: " . $result . "\n";
        
        curl_close($curl);
        
        $json=json_decode($result,true);
        $logMessage .= "JSON decode başarılı: " . (is_array($json) ? 'Evet' : 'Hayır') . "\n";
        if (is_array($json)) {
            $logMessage .= "JSON Response: " . print_r($json, true) . "\n";
        }
        
        // "session" değerini al
        $session_id = $json['msg'] ?? '';
        $logMessage .= "Session ID: " . $session_id . "\n";
        $logMessage .= "=== getsessionid TAMAMLANDI ===\n\n";
        
        // Log dosyasına yaz
        file_put_contents(\Yii::getAlias('@runtime/dia_session_log.txt'), $logMessage, FILE_APPEND | LOCK_EX);
        
        return $session_id;
    }
    public static function depoMiktar(){
        $url = self::getDiaUrl('rpr');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "rpr_raporsonuc_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "report_code" => "scf2310a",
                "param" => [
                    "_depolar" => [],
                    "_key_sis_ozelkod1" => 0,
                    "_key_sis_ozelkod2" => 0,
                    "_key_sis_ozelkod3" => 0,
                    "_key_sis_ozelkod4" => 0,
                    "_key_sis_ozelkod5" => 0,
                    "_key_sis_ozelkod6" => 0,
                    "filtreler" => [],
                    "siralama" => [],
                    "gruplama" => [],
                    "pasiflerigoster" => false,
                    "depolardaolmayangoster" => false,
                    "stokkartkodu1" => "",
                    "stokkartkodu2" => "",
                    "stokkartturleri" => [],
                    "tasarim_key" => 0,
                    "ustIslemTuruKeys" => []
                ],
                "format_type" => "json"
            ]
        ];
        
        

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($curl, CURLOPT_TIMEOUT, 120); // 2 dakika toplam işlem süresi
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 30); // 30 saniye bağlantı zaman aşımı

        $result = curl_exec($curl);
        
        // Hata kontrolü ekleyelim
        if (curl_errno($curl)) {
            $error = curl_error($curl);
            curl_close($curl);
            Yii::error("cURL error: $error", __METHOD__);
            return ['error' => $error];
        }
        curl_close($curl);
        
        // Ham sonucu loglayalım
        Yii::info("Raw API response: $result", __METHOD__);
        
        try {
            $jsonResponse = json_decode($result, true);
            
            // Eğer result anahtarı varsa ve base64 encoded ise decode et
            if (isset($jsonResponse['result']) && is_string($jsonResponse['result'])) {
                $decodedResult = base64_decode($jsonResponse['result']);
                if ($decodedResult !== false) {
                    $decodedData = json_decode($decodedResult, true);
                    if ($decodedData !== null) {
                        $jsonResponse['result'] = $decodedData;
                    } else {
                        // Base64 decode başarılı ama JSON decode başarısız, ham string'i kullan
                        $jsonResponse['result'] = $decodedResult;
                    }
                } else {
                    Yii::warning("Base64 decode başarısız oldu", __METHOD__);
                }
            }
            
            return $jsonResponse["result"]["__rows"] ?? null;
        } catch (\Exception $e) {
            Yii::error("JSON decode error: " . $e->getMessage(), __METHOD__);
            return null;
        }
    }

    public static function getallproducts(){
        $url = self::getDiaUrl('scf');

            // SESSION ID MANUEL GİRİLMELİ
            $session_id =Dia::getsessionid();
            $firma_kodu = 1;
            $donem_kodu = 1;
            // "limit": 4,
            // "offset": 0
            $data = <<<EOT
            {"scf_stokkart_detay_listele" :
                {"session_id": "$session_id",
                "firma_kodu": $firma_kodu,
                "donem_kodu": $donem_kodu
                }
            }
            EOT;

            $curl = curl_init();
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_POSTFIELDS, $data);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($data))
            );
            curl_setopt($curl, CURLOPT_URL, $url);
            $result = curl_exec($curl);
            curl_close($curl);
            return $result;
    }

    public static function getallcari(){
        $url = self::getDiaUrl('scf');

            // SESSION ID MANUEL GİRİLMELİ
            $session_id =Dia::getsessionid();
            $firma_kodu = 1;
            $donem_kodu = 1;
            // "limit": 4,
            // "offset": 0
            $data = <<<EOT
            {"scf_carikart_listele" :
                {"session_id": "$session_id",
                 "firma_kodu": $firma_kodu,
                 "donem_kodu": $donem_kodu
                }
            }
            EOT;

            $curl = curl_init();
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_POSTFIELDS, $data);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($data))
            );
            curl_setopt($curl, CURLOPT_URL, $url);
            $result = curl_exec($curl);
            curl_close($curl);
            return $result;
    }

    public static function kampanyagetir(){
        $url =  self::getDiaUrl('scf');

        // SESSION ID MANUEL GİRİLMELİ
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = <<<EOT
        {"scf_kampanya_listele" :
            {"session_id": "$session_id",
            "firma_kodu": $firma_kodu,
            "donem_kodu": $donem_kodu,
            "filters":"",
            "sorts": "",
            "params": "",
            "limit": 10,
            "offset": 0
            }
        }
        EOT;

        $curl = curl_init();
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_POSTFIELDS, $data);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_HTTPHEADER, array(
            'Content-Type: application/json',
            'Content-Length: ' . strlen($data))
        );
        curl_setopt($curl, CURLOPT_URL, $url);
        $result = curl_exec($curl);

        $json=json_decode($result,true);
        curl_close($curl);
        return $json;
    }

    public static function kampanyafiyatlarigetir(){
        $url = self::getDiaUrl('scf');

        // SESSION ID MANUEL GİRİLMELİ
        $session_id = dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;
        
        $tarih = date('Y-m-d');

        $data = <<<EOT
        {
            "scf_fiyatkart_listele": {
                "session_id": "$session_id",
                "firma_kodu": $firma_kodu,
                "donem_kodu": $donem_kodu,
                "filters": [
                    {"field": "durum", "operator": "=", "value": "A"}
                ]
            }
        }
        EOT;
        
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_POSTFIELDS, $data);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_HTTPHEADER, array(
            'Content-Type: application/json',
            'Content-Length: ' . strlen($data))
        );
        curl_setopt($curl, CURLOPT_URL, $url);
        $result = curl_exec($curl);
        
        //$json=json_decode($result,true);
        curl_close($curl);
        return $result;
    }

    public static function stokbirimgetir(){
        $url = self::getDiaUrl('rpr');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data =  [
            "rpr_raporsonuc_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "report_code" => "scf2201c",
                "tasarim_key" => 3873238,
                "param" => [ "_key" => $keyno ],
                "format_type" => "pdf"
            ]
        ];

         $data =  [
            "scf_stokkart_birimleri_listele" =>[
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
            ]

            
        ];
        $jsonData = json_encode($data);
        
            $curl = curl_init();
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            // curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
            // curl_setopt($curl, CURLOPT_SSL_VERIFYHOST, 0);
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($jsonData))
            );
      
             curl_setopt($curl, CURLOPT_URL, $url);
             $result = curl_exec($curl);
            if (curl_errno($curl)) {
                $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            } 
            else {
                $filePath = Yii::getAlias('@app/runtime/stokdata'.date("Ymdhis").'.txt');

                // Dosyaya yaz (JSON formatında yazıyoruz, ama istersen düz metin olarak da yazabilirsin)
                file_put_contents($filePath, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
                echo ["sonuc"=>'@app/runtime/stokdata'.date("Ymdhis").'.txt'];
            }
    
            curl_close($curl);
            return;
    }

    public static function stokalimsatimanalizgetir($stokkodu){
        $timestamp = date("Ymdhis");
        $logFilePath = Yii::getAlias('@app/runtime/stokanaliz_detay_log_'.$timestamp.'.txt');
        
        // Detaylı log başlangıcı
        $logContent = "=== STOK ALIM SATIS ANALIZ DETAY LOG - " . date("Y-m-d H:i:s") . " ===\n";
        $logContent .= "Stok Kodu: " . $stokkodu . "\n";
        $logContent .= "Timestamp: " . $timestamp . "\n\n";
        
        try {
            // 1. URL alma
            $logContent .= "1. URL alma işlemi başladı\n";
            $url = self::getDiaUrl('rpr');
            $logContent .= "   URL alındı: " . $url . "\n\n";
            
            // 2. Session ID alma
            $logContent .= "2. Session ID alma işlemi başladı\n";
            $session_id = Dia::getsessionid();
            $logContent .= "   Session ID alındı: " . $session_id . "\n\n";
            
            // 3. Parametreler hazırlanıyor
            $logContent .= "3. Parametreler hazırlanıyor\n";
            $firma_kodu = 1;
            $donem_kodu = 1;
            $logContent .= "   Firma Kodu: " . $firma_kodu . "\n";
            $logContent .= "   Dönem Kodu: " . $donem_kodu . "\n\n";

            // 4. Data array oluşturma
            $logContent .= "4. Data array oluşturma\n";
            $data =  [
                "rpr_raporsonuc_getir" => [
                    "session_id" => $session_id,
                    "firma_kodu" => 1,
                    "donem_kodu" => 1,
                    "report_code" => "scf9007a",
                    "tasarim_key" => 1042,
                    "param" => [ 
                  
                            "param.stokkartkodu1" => $stokkodu,
                                
                                    ],
                    "format_type" => "pdf"
                ]
            ];
            $logContent .= "   Data array oluşturuldu\n";
            $logContent .= "   Report Code: scf9007a\n";
            $logContent .= "   Tasarim Key: 1042\n";
            $logContent .= "   Format Type: pdf\n\n";

            // 5. JSON encode işlemi
            $logContent .= "5. JSON encode işlemi\n";
            $jsonData = json_encode($data);
            $logContent .= "   JSON Data uzunluğu: " . strlen($jsonData) . " karakter\n";
            $logContent .= "   JSON Data: " . $jsonData . "\n\n";

            // 6. cURL başlatma
            $logContent .= "6. cURL başlatma\n";
            $curl = curl_init();
            $logContent .= "   cURL başlatıldı\n\n";

            // 7. cURL seçenekleri ayarlama
            $logContent .= "7. cURL seçenekleri ayarlama\n";
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            $logContent .= "   CURLOPT_CUSTOMREQUEST: POST\n";
            
            curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
            $logContent .= "   CURLOPT_POSTFIELDS ayarlandı\n";
            
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            $logContent .= "   CURLOPT_RETURNTRANSFER: true\n";
            
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($jsonData))
            );
            $logContent .= "   HTTP Headers ayarlandı\n";
            $logContent .= "   Content-Type: application/json\n";
            $logContent .= "   Content-Length: " . strlen($jsonData) . "\n";
            
            curl_setopt($curl, CURLOPT_URL, $url);
            $logContent .= "   URL ayarlandı: " . $url . "\n\n";

            // 8. cURL çalıştırma
            $logContent .= "8. cURL çalıştırma\n";
            $result = curl_exec($curl);
            $logContent .= "   cURL çalıştırıldı\n";
            $logContent .= "   Response uzunluğu: " . strlen($result) . " karakter\n\n";

            // 9. Hata kontrolü
            $logContent .= "9. Hata kontrolü\n";
            if (curl_errno($curl)) {
                $error = curl_error($curl);
                $logContent .= "   cURL HATASI: " . $error . "\n";
                curl_close($curl);
                
                // Log dosyasına yazma
                file_put_contents($logFilePath, $logContent);
                
                return ['error' => $error, 'log_file' => $logFilePath];
            } else {
                $logContent .= "   cURL hatası yok\n\n";
                
                // 10. Response işleme
                $logContent .= "10. Response işleme\n";
                
                // Ham response'u kaydet
                $hamFilePath = Yii::getAlias('@app/runtime/stokdata_ham_'.$timestamp.'.txt');
                $logContent .= "   Ham dosya yolu: " . $hamFilePath . "\n";
                $writeResult = file_put_contents($hamFilePath, $result);
                $logContent .= "   Ham dosya yazma sonucu: " . ($writeResult ? "Başarılı (".strlen($result)." byte)" : "Başarısız") . "\n";
                
                // JSON decoded response'u kaydet
                $logContent .= "   JSON decode işlemi başlıyor\n";
                $jsonResponse = json_decode($result, true);
                $jsonFilePath = Yii::getAlias('@app/runtime/stokdata_json_'.$timestamp.'.txt');
                $logContent .= "   JSON dosya yolu: " . $jsonFilePath . "\n";
                $jsonWriteResult = file_put_contents($jsonFilePath, json_encode($jsonResponse, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
                $logContent .= "   JSON dosya yazma sonucu: " . ($jsonWriteResult ? "Başarılı" : "Başarısız") . "\n";
                
                // Request data'sını da kaydet
                $requestFilePath = Yii::getAlias('@app/runtime/stokdata_request_'.$timestamp.'.txt');
                $logContent .= "   Request dosya yolu: " . $requestFilePath . "\n";
                $requestWriteResult = file_put_contents($requestFilePath, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE));
                $logContent .= "   Request dosya yazma sonucu: " . ($requestWriteResult ? "Başarılı" : "Başarısız") . "\n\n";
                
                // JSON response analizi
                $logContent .= "11. JSON Response analizi\n";
                if ($jsonResponse) {
                    $logContent .= "   JSON decode başarılı\n";
                    $logContent .= "   Response keys: " . implode(', ', array_keys($jsonResponse)) . "\n";
                    if (isset($jsonResponse['code'])) {
                        $logContent .= "   Response code: " . $jsonResponse['code'] . "\n";
                    }
                    if (isset($jsonResponse['msg'])) {
                        $logContent .= "   Response message: " . $jsonResponse['msg'] . "\n";
                    }
                    if (isset($jsonResponse['result'])) {
                        $logContent .= "   Response result var: " . (is_array($jsonResponse['result']) ? count($jsonResponse['result']) . " adet" : "string") . "\n";
                    }
                } else {
                    $logContent .= "   JSON decode başarısız\n";
                    $logContent .= "   Ham response ilk 500 karakter: " . substr($result, 0, 500) . "\n";
                }
                
                curl_close($curl);
                $logContent .= "   cURL kapatıldı\n\n";
                
                // 12. Sonuç hazırlama
                $logContent .= "12. Sonuç hazırlama\n";
                $returnData = [
                    "success" => true,
                    "ham_sonuc" => $hamFilePath,
                    "json_sonuc" => $jsonFilePath,
                    "request_sonuc" => $requestFilePath,
                    "log_file" => $logFilePath,
                    "timestamp" => $timestamp
                ];
                $logContent .= "   Return data hazırlandı\n";
                $logContent .= "   Ham sonuç: " . $hamFilePath . "\n";
                $logContent .= "   JSON sonuç: " . $jsonFilePath . "\n";
                $logContent .= "   Request sonuç: " . $requestFilePath . "\n";
                $logContent .= "   Log dosyası: " . $logFilePath . "\n\n";
                
                $logContent .= "=== İŞLEM BAŞARILI BİTTİ - " . date("Y-m-d H:i:s") . " ===\n";
                
                // Log dosyasına yazma
                file_put_contents($logFilePath, $logContent);
                
                return $returnData;
            }
            
        } catch (Exception $e) {
            $logContent .= "HATA YAKALANDI: " . $e->getMessage() . "\n";
            $logContent .= "Dosya: " . $e->getFile() . "\n";
            $logContent .= "Satır: " . $e->getLine() . "\n";
            $logContent .= "Trace: " . $e->getTraceAsString() . "\n";
            
            // Log dosyasına yazma
            file_put_contents($logFilePath, $logContent);
            
            return ['error' => $e->getMessage(), 'log_file' => $logFilePath];
        }
    }

    public static function havalegonder($model){
        $tahsilatUrl = self::getDiaUrl('scf');
        $dateOnly = date('Y-m-d');
        $ssid=Dia::getsessionid();

        if($model->FisId==null)
            $fisid=$model->HareketId;
        else 
            $fisid=$model->FisId;
        $tarih=date("Y-m-d");
        $saat=date("H:i:s");
        $data = <<<EOT
            {"bcs_banka_fisi_ekle" :
                {"session_id": "$ssid",
                "firma_kodu": 1,
                "donem_kodu": 1,
                "kart": 
                    {
                    "_key_sis_ozelkod": 0,
                    "_key_sis_seviyekodu": 0,
                    "_key_sis_sube_source": {"subekodu": "44.03"},
                    "aciklama1": "GELEN HAVALE",
                    "aciklama2": "",
                    "aciklama3": "",
                    "fisno": $fisid,
                    "m_kalemler": [{"_key_bcs_banka_kredi_taksit": 0,
                                            "_key_bcs_bankahesabi": 5374478,
                                            "_key_muh_masrafmerkezi": 0,
                                            "_key_prj_proje": 0,
                                            "_key_scf_cari": {"carikartkodu": "$model->carikod"},
                                            "_key_scf_carikart_banka": 0,
                                            "_key_sis_ozelkod": 0,
                                            "aciklama": "GELEN HAVALE",
                                            "_key_sis_doviz": {"adi": "GBP"},
                                            "_key_sis_doviz_raporlama": {"adi": "GBP"},
                                            "belgeno": "",
                                            "borc_cari": "$model->Tutar,",
                                            "detay": "CHSP",
                                            "dovizkuru": "1.00",
                                            "kurfarkiborc": "0.00",
                                            "raporlamadovizkuru": "1.00"}],
                    "odemeturu": "A",
                    "saat": "$saat",
                    "tarih": "$tarih",
                    "turu": "GEHVL"
                    }
                }
            }

            EOT;

            $curl = curl_init();
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_POSTFIELDS, $data);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($data))
            );
            curl_setopt($curl, CURLOPT_URL, $url);
            $result = curl_exec($curl);

            $json=json_decode($result,true);
            curl_close($curl);
    }

    public static function tahsilatgonder($model){
        // Log başlangıcı
        $logMessage = "=== DIA::tahsilatgonder BAŞLADI ===\n";
        $logMessage .= "Tarih: " . date('Y-m-d H:i:s') . "\n";
        $logMessage .= "Model ID: " . $model->HareketId . "\n";
        $logMessage .= "FisId: " . $model->FisId . "\n";
        $logMessage .= "Tutar: " . $model->Tutar . "\n";
        $logMessage .= "OdemeYontemi: " . $model->OdemeYontemi . "\n";
        $logMessage .= "CariKod: " . $model->carikod . "\n";
        $logMessage .= "Aciklama: " . $model->Aciklama . "\n";
        
        $tahsilatUrl = self::getDiaUrl('scf');
        $logMessage .= "DIA URL: " . $tahsilatUrl . "\n";
        
        $dateOnly = date('Y-m-d');
        $ssid = Dia::getsessionid();
        $logMessage .= "Session ID: " . $ssid . "\n";
        
        // Gönderilecek veri
        $tur = null;
        $aciklama = null;
        $bankaKey = null; // Sadece KK'da kullanılacak

        if ($model->OdemeYontemi == "Nakit") {
            $tur = "NT";
            $aciklama = "Nakit Tahsilat";
            // Nakit için banka hesabı göndermiyoruz
        } elseif ($model->OdemeYontemi == "Kredi Kartı") {
            $tur = "KK";
            $aciklama = "Kredi Kartı Tahsilat";
            $bankaKey = Yii::$app->params['dia_banka_key'];
        } else {
            // Bilinmeyen ödeme yöntemi (ileride Çek vs. gelirse buraya düşer)
            $logMessage .= "Bilinmeyen OdemeYontemi: " . $model->OdemeYontemi . "\n";
            file_put_contents(\Yii::getAlias('@runtime/dia_tahsilat_log.txt'), $logMessage, FILE_APPEND | LOCK_EX);
            return json_encode([
                'success' => false,
                'message' => 'Bilinmeyen ödeme yöntemi: ' . (string)$model->OdemeYontemi,
            ], JSON_UNESCAPED_UNICODE);
        }

        $logMessage .= "Ödeme Türü: " . $tur . "\n";
        $logMessage .= "BankaKey: " . ($bankaKey !== null ? $bankaKey : 'YOK') . "\n";
        
        Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;

        // fisno (DIA için tekil belge numarası) -> Virgül içeriyorsa (çoklu fiş) HareketId kullan
        $fisno = $model->HareketId;
        if (!empty($model->FisId) && strpos((string)$model->FisId, ',') === false) {
            $fisno = $model->FisId;
        }
        $logMessage .= "Kullanılan fisno: " . $fisno . "\n";
        
        // Kalem (bankahesap sadece KK'da gönderilecek)
        $kalem = [
            "_key_scf_carikart" => ["carikartkodu" => $model->carikod],
            "_key_sis_doviz" => ["adi" => "GBP"],
            "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
            "aciklama" => "",
            "alacak" => $model->Tutar,
            "dovizkuru" => "1.00",
            "kurfarkialacak" => "0.00",
            "kurfarkiborc" => "0.00",
            "makbuzno" => "",
            "carikart" => "",
            "cariunvan" => "",
            "raporlamadovizkuru" => "1.00",
            "vade" => date('Y-m-d'),
        ];
        if ($tur === 'KK' && !empty($bankaKey)) {
            $kalem["_key_bcs_bankahesabi"] = is_numeric($bankaKey) ? (int)$bankaKey : $bankaKey;
        }

        $data = [
            "scf_carihesap_fisi_ekle" => [
                "session_id" => $ssid,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_sis_sube" => ["subekodu" => "44.01"],
                    "aciklama1" => $aciklama,
                    "aciklama2" => $model->Aciklama,
                    "aciklama3" => "",
                    "belgeno" => $model->HareketId,
                    "fisno" => $fisno,
                    "m_kalemler" => [
                        $kalem
                    ],
                    "saat" => date('H:i:s'),
                    "tarih" => date('Y-m-d'),
                    "turu" => $tur
                ]
            ]
        ];

        $jsonData = json_encode($data);
        $logMessage .= "JSON Data: " . $jsonData . "\n";
        $logMessage .= "JSON Data Length: " . strlen($jsonData) . "\n";
        
        // cURL başlat
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $tahsilatUrl);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($curl, CURLOPT_TIMEOUT, 120); // 2 dakika toplam işlem süresi
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 30); // 30 saniye bağlantı zaman aşımı
        
        $logMessage .= "cURL seçenekleri ayarlandı\n";
        $logMessage .= "cURL URL: " . $tahsilatUrl . "\n";
        $logMessage .= "cURL Method: POST\n";
        $logMessage .= "cURL Headers: Content-Type: application/json, Content-Length: " . strlen($jsonData) . "\n";

        $result = curl_exec($curl);
        $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
        $curlError = curl_error($curl);
        $curlErrno = curl_errno($curl);
        
        $logMessage .= "cURL HTTP Code: " . $httpCode . "\n";
        $logMessage .= "cURL Error No: " . $curlErrno . "\n";
        $logMessage .= "cURL Error: " . $curlError . "\n";
        $logMessage .= "cURL Response: " . $result . "\n";

        // Eğer cURL hatası varsa txt dosyasına yazdır
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents(\Yii::getAlias('@runtime/curl_hatalari.txt'), $hataMesaji, FILE_APPEND | LOCK_EX);
            $logMessage .= "cURL hatası tespit edildi ve curl_hatalari.txt'ye yazıldı\n";
        } else {
            // Sonuç
            $json = json_decode($result, true);
            $logMessage .= "JSON decode başarılı: " . (is_array($json) ? 'Evet' : 'Hayır') . "\n";
            if (is_array($json)) {
                $logMessage .= "JSON Response: " . print_r($json, true) . "\n";
            }
        }

        curl_close($curl);
        $logMessage .= "cURL kapatıldı\n";
        $logMessage .= "=== DIA::tahsilatgonder TAMAMLANDI ===\n\n";
        
        // Log dosyasına yaz
        file_put_contents(\Yii::getAlias('@runtime/dia_tahsilat_log.txt'), $logMessage, FILE_APPEND | LOCK_EX);
        
        return $result;
    }
    public static function cekiletahsilatgonder($model){
        // Log başlangıcı
        $logMessage = "=== DIA::tahsilatgonder BAŞLADI ===\n";
        $logMessage .= "Tarih: " . date('Y-m-d H:i:s') . "\n";
        $logMessage .= "Model ID: " . $model->HareketId . "\n";
        $logMessage .= "FisId: " . $model->FisId . "\n";
        $logMessage .= "Tutar: " . $model->Tutar . "\n";
        $logMessage .= "OdemeYontemi: " . $model->OdemeYontemi . "\n";
        $logMessage .= "CariKod: " . $model->carikod . "\n";
        $logMessage .= "Aciklama: " . $model->Aciklama . "\n"; 
        
        $tahsilatUrl = self::getDiaUrl('bcs');
        $logMessage .= "DIA URL: " . $tahsilatUrl . "\n";
        
        $dateOnly = date('Y-m-d');
        $ssid = Dia::getsessionid();
        $logMessage .= "Session ID: " . $ssid . "\n";
        
        Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;

        // fisno (DIA için tekil belge numarası) -> Virgül içeriyorsa (çoklu fiş) HareketId kullan
        $fisno = $model->HareketId;
        if (!empty($model->FisId) && strpos((string)$model->FisId, ',') === false) {
            $fisno = $model->FisId;
        }
        $logMessage .= "Kullanılan fisno: " . $fisno . "\n";
        $subeKodu= Yii::$app->guser->identity->branch_code;
        $sube= Branches::find()->where(["branch_code"=>$subeKodu])->one();
        $bankaKey = is_numeric(Yii::$app->params['dia_banka_key']) ? (int)Yii::$app->params['dia_banka_key'] : Yii::$app->params['dia_banka_key'];

        $data = [
            "bcs_cs_bordro_ekle" => [
                "session_id" => $ssid,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_sis_sube" => $sube->_key,
                    "aciklama1" => "Çek ile Ödeme",
                    "aciklama2" => $model->Aciklama,
                    "aciklama3" => "",
                    "bordrono" => $model->HareketId,
                    "bordrotarihi" => date('Y-m-d'),
                    "raporlamadovizkuru" => "1.00",
                    "saat" => date('H:i:s'),
                    "teminatdurumu" => "H",
                    "belgeturu" =>2,
                    "turu" => "CG",
                    "m_ceksenet" => [
                        [
                            "_key_bcs_bankahesabi" =>  5374478,
                            "_key_muh_masrafmerkezi" => 0,
                            "_key_muh_masrafmerkezi_donemsiz" => 0,
                            "_key_prj_proje" => 0,
                            "_key_scf_carikart" => 0,
                            "_key_scf_malzeme_baglantisi" => 0,
                            "_key_sis_doviz" => ["adi" => "GBP"],
                            "_key_sis_ozelkod" => 0,
                            "_key_sis_seviyekodu" => 0,
                            "aciklama" => $model->Aciklama,
                            "bankaadi" => "",
                            "borclu" => $model->carikod,
                            "cirolu" => "H",
                            "hesapno" => "",
                            "iban" => "",
                            "kefil" => "",
                            "kefil2" => "",
                            "kefil2bilgi" => "",
                            "kefilbilgi" => "",
                            "muhabirsube" => "",
                            "odemeyeri" => "",
                            "subekodu" => $subeKodu,
                            "tutar" => $model->Tutar,
                            "tutar_cari" => $model->Tutar,
                            "vade" => $model->vadetarihi,
                            
                        ]
                    ]
                ]
            ]
        ];

        $jsonData = json_encode($data);
        $logMessage .= "JSON Data: " . $jsonData . "\n";
        $logMessage .= "JSON Data Length: " . strlen($jsonData) . "\n";
        
        // cURL başlat
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $tahsilatUrl);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($curl, CURLOPT_TIMEOUT, 120); // 2 dakika toplam işlem süresi
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 30); // 30 saniye bağlantı zaman aşımı
        
        $logMessage .= "cURL seçenekleri ayarlandı\n";
        $logMessage .= "cURL URL: " . $tahsilatUrl . "\n";
        $logMessage .= "cURL Method: POST\n";
        $logMessage .= "cURL Headers: Content-Type: application/json, Content-Length: " . strlen($jsonData) . "\n";

        $result = curl_exec($curl);
        $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
        $curlError = curl_error($curl);
        $curlErrno = curl_errno($curl);
        
        $logMessage .= "cURL HTTP Code: " . $httpCode . "\n";
        $logMessage .= "cURL Error No: " . $curlErrno . "\n";
        $logMessage .= "cURL Error: " . $curlError . "\n";
        $logMessage .= "cURL Response: " . $result . "\n";

        // Eğer cURL hatası varsa txt dosyasına yazdır
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents(\Yii::getAlias('@runtime/curl_hatalari.txt'), $hataMesaji, FILE_APPEND | LOCK_EX);
            $logMessage .= "cURL hatası tespit edildi ve curl_hatalari.txt'ye yazıldı\n";
        } else {
            // Sonuç
            $json = json_decode($result, true);
            $logMessage .= "JSON decode başarılı: " . (is_array($json) ? 'Evet' : 'Hayır') . "\n";
            if (is_array($json)) {
                $logMessage .= "JSON Response: " . print_r($json, true) . "\n";
            }
        }

        curl_close($curl);
        $logMessage .= "cURL kapatıldı\n";
        $logMessage .= "=== DIA::tahsilatgonder TAMAMLANDI ===\n\n";
        
        // Log dosyasına yaz
        file_put_contents(\Yii::getAlias('@runtime/dia_tahsilat_log.txt'), $logMessage, FILE_APPEND | LOCK_EX);
        
        return $result;
    }

    public static function iadegonder($model){
        $tahsilatUrl = self::getDiaUrl('scf');
        $dateOnly = date('Y-m-d');
        $ssid=Dia::getsessionid();
        // Gönderilecek veri

        if( $model->tur=="cash"){
            $tur="NÖ";
            $aciklama="Cash refund";
            $banka=0;
        }
        else if($model->tur=="credit"){
            $tur="KI";
            $aciklama="Kredi Kartı ile Iade";
            $banka=Yii::$app->params['dia_banka_key'];
        }
        else if($model->tur=="check"){
            $tur="ÇÖ";
            $aciklama="Çek ile Iade";
            $banka=0;
        }
        Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;
        $fisid = $model->FisId;
        $data = [
            "scf_carihesap_fisi_ekle" => [
                "session_id" => $ssid,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_sis_sube" => ["subekodu" => "44.01"],
                    "aciklama1" => $aciklama,
                    "aciklama2" => $model->aciklama,
                    "aciklama3" => "",
                    "belgeno" => $model->FisId,
                    "fisno" => $fisid,
                    "m_kalemler" => [
                        [
                            "_key_bcs_bankahesabi"=> $banka,
                            "_key_scf_carikart" => ["carikartkodu" => $model->MusteriId],
                            "_key_sis_doviz" => ["adi" => "GBP"],
                            "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                            "aciklama" => "",
                            "alacak" => $model->Toplamtutar,
                            "dovizkuru" => "1.00",
                            "kurfarkialacak" => "0.00",
                            "kurfarkiborc" => "0.00",
                            "makbuzno" => "",
                            "carikart" => "",
                            "cariunvan" => "",
                            "raporlamadovizkuru" => "1.00",
                            "vade" => date('Y-m-d'),
                        ]
                    ],
                    "saat" => date('H:i:s'),
                    "tarih" => date('Y-m-d'),
                    "turu" => $tur
                ]
            ]
        ];

        $jsonData = json_encode($data);
        // cURL başlat
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $tahsilatUrl);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);

        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);

        // Eğer cURL hatası varsa log'a yaz
        if (curl_errno($curl)) {
            \Yii::error('Dia iadegonder cURL hatası: ' . curl_error($curl));
        } else {
            // Sonuç
            $json = json_decode($result, true);
            \Yii::info('Dia iadegonder API Response: ' . print_r($json, true));
        }

        curl_close($curl);
    }

    public static function numarailefisgonder($fisno){
        $tahsilatUrl = self::getDiaUrl('scf');
        $dateOnly = date('Y-m-d');
        $ssid=Dia::getsessionid();
        $fis=Satisfisleri::find()->where(["FisNo"=>$fisno])->one();
        $satirlar=$fis->satissatirlari;
        $kalemler=[];
        $sira=1;
        foreach ($satirlar as $satir) {
            $sd=[];
            $stok=Urunler::find()->where(["Stokkodu"=>$satir->StokKodu])->one();
            if($satir->BirimTipi=="UNIT")
                $birimkey=$stok->BirimKey1;
            else
                $birimkey=$stok->BirimKey2;
            $indirim=0;
            if($satir->Iskonto>0)
                $indirim=round((($satir->BirimFiyti*$satir->Miktar)*$satir->Iskonto/100),2);
            $satirtutari=$satir->BirimFiyat*$satir->Miktar*(1-$satir->Iskonto/100);
            $satirkdv=$satirtutari*$satir->vat/100;
            $sd=[
                "_key_kalemturu" => ["stokkartkodu" => $satir->StokKodu],
                "_key_scf_kalem_birimleri" => $birimkey,
                "_key_sis_depo_source" => ["depokodu" => "44.03.01"],
                "_key_sis_doviz" => ["adi" => "GBP"],
                "anamiktar" => $satir->Miktar,
                "birimfiyati" => $satir->BirimFiyat,
                "dovizkuru" => "1.000000",
                "irstarih" => $fis->Fistarihi,
                "kalemturu" => "MLZM",
                "kdv" => $stok->Vat,
                "kdvdurumu" => "H",
                "indirim1"=>$indirim,
                "kdvtutari" => $satirkdv,
                "miktar" =>  $satir->Miktar,
                "sirano" => $sira,
                "sonbirimfiyati" =>$satir->BirimFiyat,
                "tutari" => $satirtutari,
                "yerelbirimfiyati" =>$satir->BirimFiyat,
                "m_varyantlar" => []
            ];
            $kalemler[]=$sd;
            $sira++;
        }
   
        $data = [
            "scf_fatura_ekle" => [
                "session_id" => $ssid,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_scf_carikart" => ["carikartkodu" =>$fis->musteri->Kod],
                    "_key_scf_odeme_plani" => ["kodu" => "00000001"],
                    "_key_sis_depo_source" => ["depokodu" => $fis->kasa->depokodu??"44.03.01"],
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                    "_key_sis_sube_source" => ["subekodu" => $fis->kasa->subeodu??"44.03"],
                    "aciklama1" => "musteriid: ",
                    "aciklama2" => "fisno: ",
                    "belgeno" =>  $fis->FisNo,
                    "fisno" => $fis->FisNo,
                    "karsifirma" => "C",
                    "kasafisno" => $fis->FisNo,
                    "dovizkuru" => "1.000000",
                    "kategori" => "F",
                    "m_kalemler" => $kalemler,
                    "raporlamadovizkuru" => "1.000000",
                    "saat" => "14:55:53",
                    "sevkadresi1" => "YILDIRIMÖNÜ MAH. ÇAMDALI SOK. NO:118",
                    "sevkadresi2" => "",
                    "sevkadresi3" => "Keçiören ANKARA",
                    "tarih" => $dateOnly,
                    "turu" => 2
                ]
            ]
        ];
        
        $jsonData = json_encode($data);
       // echo $jsonData;
        // cURL başlat
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL,  $tahsilatUrl); // Burada $newUrl kullanıyoruz
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false); // Sertifika doğrulamasını kapatıyoruz (test amaçlı)
        
        $result = curl_exec($curl);
        
        // Eğer cURL hatası varsa yazdır
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
           $sonuc=0;
        } else {
            $sonuc=1;
            // Sonuç
            //
             $json = json_decode($result, true);
             $fis->diakey=$json["key"];
             if(!$fis->save()){
                echo "<pre>";
                print_r(json_encode($fis->errors)); // API'nin dönüşünü yazdır
                echo "</pre>";
             }
             return 0;

        }  
        curl_close($curl);
         return $sonuc; 
    }
    public static function fisgonder($fis,$tur){
        $tahsilatUrl = self::getDiaUrl('scf');
        $dateOnly = date('Y-m-d');
        $ssid=Dia::getsessionid();
        if($tur==2)
            $satirlar=Satissatirlari::find()->where(["FisNo"=>$fis->FisNo])->all();
        else if($tur=7)
            $satirlar=Iadesatirlari::find()->where(["FisNo"=>$fis->FisNo])->all();
        $kalemler=[];
        $sira=1;
            
        foreach ($satirlar as $satir) {
            $sd=[];
            if($satir->ToplamTutar>0.01){
                $stok=Urunler::find()->where(["StokKodu"=>$satir->StokKodu])->one();
                if($satir->BirimTipi=="UNIT")
                    $birimkey=$stok->BirimKey1;
                else
                    $birimkey=$stok->BirimKey2;

                $satirtutari=$satir->BirimFiyat*$satir->Miktar*(1-$satir->Iskonto/100);
                $satirkdv=$satirtutari*$satir->vat/100;
                $sd=[
                    "_key_kalemturu" => ["stokkartkodu" => $satir->StokKodu],
                    "_key_scf_kalem_birimleri" => $birimkey,
                    "_key_sis_depo_source" => ["depokodu" => "44.01.01"],
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "anamiktar" => $satir->Miktar,
                    "birimfiyati" => $satir->BirimFiyat,
                    "dovizkuru" => "1.000000",
                    "irstarih" => $fis->Fistarihi,
                    "kalemturu" => "MLZM",
                    "kdv" => $stok->Vat,
                    "kdvdurumu" => "H",
                    "indirim1"=> $satir->Iskonto,
                    "kdvtutari" => $satirkdv,
                    "miktar" =>  $satir->Miktar,
                    "sirano" => $sira,
                    "sonbirimfiyati" =>$satir->BirimFiyat,
                    "tutari" => $satirtutari,
                    "yerelbirimfiyati" =>$satir->BirimFiyat,
                    "m_varyantlar" => []
                ];
                $kalemler[]=$sd;
                $sira++;
            }
        }
   
        $data = [
            "scf_fatura_ekle" => [
                "session_id" => $ssid,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_scf_carikart" => ["carikartkodu" =>$fis->MusteriId],
                    "_key_sis_depo_source" => ["depokodu" => $fis->kasa->depokodu??"44.03.01"],
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                    "_key_sis_sube_source" => ["subekodu" => 44.03],
                    "_key_scf_satiselemani"=>(int)$fis->satispersoneli,
                    "aciklama1" => "musteriid: ",
                    "aciklama2" => "fisno: ",
                    "belgeno" =>  $fis->FisNo,
                    "belgeno2" =>  $fis->FisNo,
                    "fisno" => $fis->FisNo,
                    "karsifirma" => "C",
                    "kasafisno" => $fis->FisNo,
                    "dovizkuru" => "1.000000",
                    "kategori" => "F",
                    "m_kalemler" => $kalemler,
                    "raporlamadovizkuru" => "1.000000",
                    "saat" => date('H:i:s'),
                    "sevkadresi1" => "",
                    "sevkadresi2" => "",
                    "sevkadresi3" => "",
                    "tarih" => $dateOnly,
                    "turu" => $tur,
                    "ekalan5" =>  $fis->tillname //$fis->satispersoneli,
                ]
            ]
        ];
        
        $jsonData = json_encode($data);
         //echo $jsonData;
        // cURL başlat

        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL,  $tahsilatUrl); // Burada $newUrl kullanıyoruz
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false); // Sertifika doğrulamasını kapatıyoruz (test amaçlı)
        
        $result = curl_exec($curl);
        
        // Eğer cURL hatası varsa yazdır
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
           $sonuc=["code"=>0,"hata"=>$hataMesaji];
        } else {
             $json = json_decode($result, true);
            //   echo $result;
     
             if($json["code"]==200){
                if($json["key"]){
                    $fis->diakey=$json["key"];
                    if(!$fis->save()){
                        // echo "<pre>";
                        // print_r(json_encode($fis->errors)); // API'nin dönüşünü yazdır
                        // echo "</pre>";
                    }
                 }
                 $sonuc= $json;
             } 
             else 
             $sonuc= $json;
        }   
        curl_close($curl);
        return $sonuc; 
    }

    public static function gunlukfaturagetir($faturano){
        $url = self::getDiaUrl('rpr');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "rpr_raporsonuc_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "report_code" => "scf2201c",
                "tasarim_key" => 1200,
                "param" => [
                    "_key" => "faturano:".$faturano,
                ],
                "format_type" => "pdf"
            ]
        ];
        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_HTTPHEADER, array(
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData))
        );
        curl_setopt($curl, CURLOPT_URL, $url);
        $result = curl_exec($curl);

        $json=json_decode($result,true);
        curl_close($curl);
        print_r($json);
    }

    public static function faturapdfgetir($keyno){
        
        $url = self::getDiaUrl('rpr');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data =  [
            "rpr_raporsonuc_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "report_code" => "scf2201c",
                "tasarim_key" => 3873238,
                "param" => [ "_key" => $keyno ],
                "format_type" => "pdf"
            ]
        ];
        $jsonData = json_encode($data);
        
            $curl = curl_init();
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            // curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
            // curl_setopt($curl, CURLOPT_SSL_VERIFYHOST, 0);
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($jsonData))
            );
      
             curl_setopt($curl, CURLOPT_URL, $url);
             $result = curl_exec($curl);
            if (curl_errno($curl)) {
                $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            } 
            else {
                // Sonuç
                // $json = json_decode($result, true);
                // echo "<pre>";
                // print_r($json); // API'nin dönüşünü yazdır
                // echo "</pre>";
            }
    
             curl_close($curl);

        
        // $json=json_decode($result,true);
        // curl_close($curl);
        // print_r($json);
        
        //$pdfContent = base64_decode($json['result']);
        //echo $result["result"];
        // // PDF'in geçerli olup olmadığını kontrol etme
        // if (strpos($pdfContent, '%PDF') !== 0) {
        //     throw new \yii\web\HttpException(400, 'Geçersiz PDF dosyası');
        // }
        
        // // Yanıtı PDF olarak gönderme
        // \Yii::$app->response->format = Response::FORMAT_RAW;
        // \Yii::$app->response->headers->add('Content-Type', 'application/pdf');
        // \Yii::$app->response->headers->add('Content-Disposition', 'attachment; filename="belge.pdf"');
        
        //return $pdfContent;
    }

    public static function iadefaturapdfgetir($keyno){
        $url = self::getDiaUrl('rpr');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data =  [
            "rpr_raporsonuc_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "report_code" => "scf2201c",
                "tasarim_key" => 5374460,
                "param" => [ "_key" => $keyno ],
                "format_type" => "pdf"
            ]
        ];
        $jsonData = json_encode($data);
        
            $curl = curl_init();
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            // curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
            // curl_setopt($curl, CURLOPT_SSL_VERIFYHOST, 0);
            curl_setopt($curl, CURLOPT_HTTPHEADER, array(
                'Content-Type: application/json',
                'Content-Length: ' . strlen($jsonData))
            );
      
             curl_setopt($curl, CURLOPT_URL, $url);
             $result = curl_exec($curl);
            if (curl_errno($curl)) {
                $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            } 
            else {
                // Sonuç
                // $json = json_decode($result, true);
                // echo "<pre>";
                // print_r($json); // API'nin dönüşünü yazdır
                // echo "</pre>";
            }
    
             curl_close($curl);

        
        // $json=json_decode($result,true);
        // curl_close($curl);
        // print_r($json);
        
        //$pdfContent = base64_decode($json['result']);
        //echo $result["result"];
        // // PDF'in geçerli olup olmadığını kontrol etme
        // if (strpos($pdfContent, '%PDF') !== 0) {
        //     throw new \yii\web\HttpException(400, 'Geçersiz PDF dosyası');
        // }
        
        // // Yanıtı PDF olarak gönderme
        // \Yii::$app->response->format = Response::FORMAT_RAW;
        // \Yii::$app->response->headers->add('Content-Type', 'application/pdf');
        // \Yii::$app->response->headers->add('Content-Disposition', 'attachment; filename="belge.pdf"');
        
        //return $pdfContent;
    }  
    public static function siparisgondermobil($fis,$tur=1){
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;
        if($tur==1)
            
            $satirlar=$fis->getSatinAlmaSiparisFisSatirs()->with('urun')->all();
        else 
            $satirlar=$fis->getSatissatirlari()->all();
        $sira=1;

        $satispersoneli=Satiscilar::find()->where(["kodu"=>$fis->satispersoneli])->one();
        foreach ($satirlar as $satir) {
            $sd=[];
            
            $stok = null;
            $birimAlani = null;

            if ($satir instanceof \app\models\SatinAlmaSiparisFisSatir) { // Satınalma sipariş satırı ise
                if (!$satir->urun) continue; // İlişkili ürün yoksa atla
                $stok = $satir->urun;
                $birimAlani = $satir->birim; // birim alanı kullanılıyor
            } else { // Satış sipariş satırı ise (varsayılan)
                $stok = Urunler::find()->where(["StokKodu" => $satir->StokKodu])->one();
                if (!$stok) continue;
                $birimAlani = $satir->BirimTipi; // BirimTipi alanı olduğu varsayılıyor
            }

            if($birimAlani=="UNIT")
                $birimkey=$stok->BirimKey1;
            else
                $birimkey=$stok->BirimKey2;

            $satirtutari=0;//$satir->BirimFiyat*$satir->Miktar*(1-$satir->Iskonto/100);
            $satirkdv=0;//$satirtutari*$satir->vat/100;
            $sd=[
                "_key_kalemturu" => ["stokkartkodu" => $stok->StokKodu],
                "_key_scf_kalem_birimleri" => $birimkey,
                    "_key_sis_depo_source" => ["depokodu" => "44.03.01"],
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "anamiktar" =>$satir->Miktar,
                    "birimfiyati" =>$satir->BirimFiyat??0,
                    "dovizkuru" => "1.000000",
                    "kalemturu" => "MLZM",
                    "kdv" =>  $stok->Vat,
                    "kdvdurumu" => "H",
                    "kdvtutari" =>$satirkdv,
                    "miktar" =>  $satir->Miktar,
                    "onay" => "KABUL",
                    "rezervasyon" => "H",
                    "siptarih" => $fis->Fistarihi,
                    "sirano" => $sira,
                    "sonbirimfiyati" => $satir->BirimFiyat??0,
                    "tutari" => $satirtutari,
                    "yerelbirimfiyati" => $satir->BirimFiyat??0,
                "m_varyantlar" => []
            ];
            $kalemler[]=$sd;
            $sira++;
        }
        
        $data = [
            "scf_siparis_ekle" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_scf_carikart" => ["carikartkodu" =>$fis->MusteriId],
                    "_key_sis_depo_source" => ["depokodu" => "44.03.01"],
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                    "_key_sis_ozelkod1" => 0,
                    "_key_sis_ozelkod2" => 0,
                    "_key_sis_sube_source" => ["subekodu" => "44.03"],
                    "aciklama1" => $fis->comment,
                    "teslimattarihi"=> $fis->deliverydate,
                    "_key_scf_satiselemani"=>$satispersoneli->_key,
                    "dovizkuru" => "1.000000",
                    "ekalan1" => "",
                    "fisno" => $fis->FisNo,
                    "m_kalemler" => $kalemler,
                    "net" => "0.000000",
                    "netdvz" => "0.000000",
                    "odemeislemli" => "f",
                    "odemeli" => "f",
                    "onay" => "KABUL",
                    "ortalamavade" => $fis->Fistarihi,
                    "raporlamadovizkuru" => "1.000000",
                    "saat" => date("H:i:s"),
                    "tarih" => date("Y-m-d"),
                    "teslimat_adres1" => "",
                    "teslimat_adres2" => "",
                    "teslimat_adsoyad" => "",
                    "teslimat_ceptel" => "",
                    "teslimat_ilce" => "",
                    "teslimat_key_sis_sehirler" => 0,
                    "teslimat_telefon" => "",
                    "toplam" => "00.000000",
                    "toplamdvz" => "0.000000",
                    "toplamindirim" => "0.000000",
                    "toplamindirimdvz" => "0.000000",
                    "toplamkdv" => "0.000000",
                    "toplamkdvdvz" => "0.000000",
                    "toplammasraf" => "0.000000",
                    "toplammasrafdvz" => "0.000000",
                    "turu" => 2
                ]
            ]
        ];
        
        $jsonData = json_encode($data);
       // echo $jsonData;
        // cURL başlat
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL,  $url); // Burada $newUrl kullanıyoruz
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false); // Sertifika doğrulamasını kapatıyoruz (test amaçlı)
        
        $result = curl_exec($curl);
        
        print_r($result);
        // Eğer cURL hatası varsa yazdır
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
           $sonuc=0;
        } else {
             $sonuc=1;
            // // Sonuç
            // //
              $json = json_decode($result, true);
             

                echo "<pre>";
                print_r($json);
                print_r(json_encode($fis->errors)); // API'nin dönüşünü yazdır
                echo "</pre>";
        
            //  return 1;

        }   
        curl_close($curl);
        return $sonuc; 
          
    }    
    //$fis
    public static function Si($fis,$tur=1){
        $logFile = Yii::getAlias('@runtime') . '/siparisgonder_log_' . date('Ymd_His') . '.txt';
        $logContent = '';
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;
        if($tur==1)          
            $satirlar=$fis->getSatinAlmaSiparisFisSatirs()->with('urun')->all();
        else 
            $satirlar=$fis->getSatissatirlari()->all();
        $sira=1;
        $kalemler = [];
        foreach ($satirlar as $satir) {
            $sd=[];
            $stok = null;
            $birimAlani = null;
            if($tur==1)
                $stno=$satir->urun_id;
            else 
                $stno=$stok->StokKodu;

            if ($satir instanceof \app\models\SatinAlmaSiparisFisSatir) { // Satınalma sipariş satırı ise
                if (!$satir->urun) continue; // İlişkili ürün yoksa atla
                $stok = $satir->urun;
                $birimAlani = $satir->birim; // birim alanı kullanılıyor
            } else { // Satış sipariş satırı ise (varsayılan)
                $stok = Urunler::find()->where(["StokKodu" =>$stno ])->one();
                if (!$stok) continue;
                $birimAlani = $satir->BirimTipi; // BirimTipi alanı olduğu varsayılıyor
            }

            if($birimAlani=="UNIT")
                $birimkey=$stok->BirimKey1;
            else
                $birimkey=$stok->BirimKey2;

            $satirtutari=0;//$satir->BirimFiyat*$satir->Miktar*(1-$satir->Iskonto/100);
            $satirkdv=0;//$satirtutari*$satir->vat/100;
            $sd=[
                "_key_kalemturu" => ["stokkartkodu" => $stno],
                "_key_scf_kalem_birimleri" => $birimkey,
                "_key_sis_depo_source" => ["depokodu" => "44.03.01"],
                "_key_sis_doviz" => ["adi" => "GBP"],
                "anamiktar" =>$satir->miktar,
                "birimfiyati" =>$satir->BirimFiyat??0,
                "dovizkuru" => "1.000000",
                "kalemturu" => "MLZM",
                "kdv" =>  $stok->Vat,
                "kdvdurumu" => "H",
                "kdvtutari" =>$satirkdv,
                "miktar" =>  $satir->miktar,
                "onay" => "KABUL",
                "rezervasyon" => "H",
                "siptarih" => $fis->satinalmasiparisfis->tarih,
                "sirano" => $sira,
                "sonbirimfiyati" => $satir->BirimFiyat??0,
                "tutari" => $satirtutari,
                "yerelbirimfiyati" => $satir->BirimFiyat??0,
                "m_varyantlar" => []
            ];
            $kalemler[]=$sd;
            $sira++;
        }
        $data = [
            "scf_siparis_ekle" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_scf_carikart" => ["carikartkodu" =>$fis->tedarikci->tedarikci_kodu],
                    "_key_sis_depo_source" => ["depokodu" => "44.03.01"],
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                    "_key_sis_ozelkod1" => 0,
                    "_key_sis_ozelkod2" => 0,
                    "_key_sis_sube_source" => ["subekodu" => "44.03"],
                    "aciklama1" => "",
                    "dovizkuru" => "1.000000",
                    "ekalan1" => "",
                    "fisno" => $fis->fisno,
                    "m_kalemler" => $kalemler,
                    "net" => "0.000000",
                    "netdvz" => "0.000000",
                    "odemeislemli" => "f",
                    "odemeli" => "f",
                    "onay" => "KABUL",
                    "ortalamavade" => $fis->satinalmasiparisfis->tarih,
                    "raporlamadovizkuru" => "1.000000",
                    "saat" => date("H:i:s"),
                    "tarih" => date("Y-m-d"),
                    "teslimat_adres1" => "",
                    "teslimat_adres2" => "",
                    "teslimat_adsoyad" => "",
                    "teslimat_ceptel" => "",
                    "teslimat_ilce" => "",
                    "teslimat_key_sis_sehirler" => 0,
                    "teslimat_telefon" => "",
                    "toplam" => "00.000000",
                    "toplamdvz" => "0.000000",
                    "toplamindirim" => "0.000000",
                    "toplamindirimdvz" => "0.000000",
                    "toplamkdv" => "0.000000",
                    "toplamkdvdvz" => "0.000000",
                    "toplammasraf" => "0.000000",
                    "toplammasrafdvz" => "0.000000",
                    "turu" => 1
                ]
            ]
        ];
        
        $jsonData = json_encode($data);
       // echo $jsonData;
        // cURL başlat
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL,  $url); // Burada $newUrl kullanıyoruz
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false); // Sertifika doğrulamasını kapatıyoruz (test amaçlı)
        
        $result = curl_exec($curl);
        print_r($result);
        // Eğer cURL hatası varsa yazdır
        $logContent .= "[".date('Y-m-d H:i:s')."] API Response: " . $result . "\n";
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
           $sonuc=0;
            $errorMsg = 'cURL hatası: ' . curl_error($curl);
            $logContent .= "[".date('Y-m-d H:i:s')."] ERROR: $errorMsg\n";
            file_put_contents($logFile, $logContent);
            curl_close($curl);
            return 0;
        } else {
            $json = json_decode($result, true);
            $logContent .= "[".date('Y-m-d H:i:s')."] JSON Decode: " . print_r($json, true) . "\n";
            $logContent .= "[".date('Y-m-d H:i:s')."] Fis Errors: " . print_r($fis->errors, true) . "\n";
            file_put_contents($logFile, $logContent);
            curl_close($curl);
            return 1;
        }
    }
    public static function siparislistele($startDate,$endDate){
        if($startDate == null){
            $startDate = date('Y-m-d 00:00:00', strtotime('-1 day'));
        }
        if($endDate == null){
            $endDate = date('Y-m-d 23:59:59');
        }
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_siparis_listele" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" => [
                    ["field" => "_cdate", "operator" => ">=", "value" => $startDate],
                    ["field" => "_cdate", "operator" => "<=", "value" => $endDate],
                    ["field" => "turu", "operator" => "=", "value" => 1],
                    ["field" => 'onay', "operator" => "=", "value" => "KABUL" ]
                ],
                "sorts" => "",
                "params" => "",
                "limit" => 1000, // Limit ekle
                "offset" => 0
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        // Timeout ayarları ekle
        curl_setopt($curl, CURLOPT_TIMEOUT, 120); // 2 dakika
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 30); // 30 saniye bağlantı timeout

        $result = curl_exec($curl);
        if (curl_errno($curl)) {
            Yii::error('Sipariş listele cURL hatası: ' . curl_error($curl), 'dia');
            curl_close($curl);
            return null;
        } else {
            $json = json_decode($result, true);
            curl_close($curl);
            return $json['result'] ?? null;
        }
    }
    public static function siparislisteleayrintili($startDate,$endDate){
        if($startDate == null){
            $startDate = date('Y-m-d 00:00:00', strtotime('-1 day'));
        }
        if($endDate == null){
            $endDate = date('Y-m-d 23:59:59');
        }
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;
 
        $data = [
            "scf_siparis_listele_ayrintili" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" => [
                    ["field" => "_cdate", "operator" => ">=", "value" => $startDate],
                    ["field" => "_cdate", "operator" => "<=", "value" => $endDate],
                    ["field" => "turu", "operator" => "IN", "value" => "1,2,3"],
                ],
                "sorts" => "",
                "params" => "",
                "offset" => 0
            ]
        ];

        // Log the request data
        $requestLogPath = Yii::getAlias('@app/runtime/siparis_ayrintili_request_'.date("Ymdhis").'.txt');
        $requestLog = "URL: " . $url . "\n";
        $requestLog .= "Session ID: " . $session_id . "\n";
        $requestLog .= "Start Date: " . $startDate . "\n";
        $requestLog .= "End Date: " . $endDate . "\n";
        $requestLog .= "Request Data: \n" . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
       // file_put_contents($requestLogPath, $requestLog);

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        // Timeout ayarları ekle
        curl_setopt($curl, CURLOPT_TIMEOUT, 60); // 1 dakika
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 15); // 15 saniye bağlantı timeout

        $result = curl_exec($curl);
        
        if (curl_errno($curl)) {
            $error = curl_error($curl);
            Yii::error('Sipariş ayrıntı cURL hatası: ' . $error, 'dia');
            curl_close($curl);
            return null;
        } else {
            $json = json_decode($result, true);
            curl_close($curl);
            return $json['result'] ?? null;
        }
    }
    public static function siparislisteleayrintilibykey($startDate,$endDate, $siparis_key){
        if($startDate == null){
            $startDate = date('Y-m-d 00:00:00', strtotime('-1 day'));
        }
        if($endDate == null){
            $endDate = date('Y-m-d 23:59:59');
        }
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;
 
        $data = [
            "scf_siparis_listele_ayrintili" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" => [
                    ["field" => "_cdate", "operator" => ">=", "value" => $startDate],
                    ["field" => "_cdate", "operator" => "<=", "value" => $endDate],
                    ["field" => "_key_scf_siparis", "operator" => "=", "value" => $siparis_key]
                ],
                "sorts" => "",
                "params" => "",
                "offset" => 0
            ]
        ];

        // Log the request data
        $requestLogPath = Yii::getAlias('@app/runtime/siparis_ayrintili_request_'.date("Ymdhis").'.txt');
        $requestLog = "URL: " . $url . "\n";
        $requestLog .= "Session ID: " . $session_id . "\n";
        $requestLog .= "Start Date: " . $startDate . "\n";
        $requestLog .= "End Date: " . $endDate . "\n";
        $requestLog .= "Request Data: \n" . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
       // file_put_contents($requestLogPath, $requestLog);

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        // Timeout ayarları ekle
        curl_setopt($curl, CURLOPT_TIMEOUT, 60); // 1 dakika
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 15); // 15 saniye bağlantı timeout

        $result = curl_exec($curl);
        
        if (curl_errno($curl)) {
            $error = curl_error($curl);
            Yii::error('Sipariş ayrıntı cURL hatası: ' . $error, 'dia');
            curl_close($curl);
            return null;
        } else {
            $json = json_decode($result, true);
            curl_close($curl);
            return $json['result'] ?? null;
        }
    }
    public static function urunBilgiGetir($stokkartkodu){
        $url = self::getDiaUrl('scf');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_urun_ozellik_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" =>[
                    ["field" => "durum", "operator" => "=", "value" => "A"],
                    ["field" => "stokkartkodu","operator" => "=", "value" => $stokkartkodu],
                ],
                "sorts" =>  [
                    ["field" => "stokkartkodu", "sorttype" => "DESC"]],
                "params" => [
                    "_key_sis_depo" => 0,
                    "_key_sis_depo_filtre" => 0,
                    "tarih" => "2099-12-31",

                ],
                "limit" => 5,
                "offset" => 0
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            return null;
        } else {
            $json = json_decode($result, true);
            return $json;
        }
        curl_close($curl);
    }
    public static function cariKartGetir($cari_key){
        $url = self::getDiaUrl('scf');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_carikart_getir" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "key" => $cari_key
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            return null;
        } else {
            $json = json_decode($result, true);
            return $json;
        }
        curl_close($curl);
    }
    public static function cariKartListele($cariKartKodlari = null){
        $url = self::getDiaUrl('scf');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_carikart_listele" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" => [
                    ["field" => "carikartkodu", "operator" => "IN", "value" => "$cariKartKodlari"]
                ],
            ]
        ];

        $jsonData = json_encode($data);
        // Log REQUEST
        try {
            $logPrefix = '[' . date('Y-m-d H:i:s') . '] ';
            $reqLog = $logPrefix . 'REQUEST scf_carikart_listele carikodu=' . (string)$cariKartKodlari . ' payload=' . $jsonData . "\n";
            file_put_contents(\Yii::getAlias('@app/runtime/dia_cari_listele_log.txt'), $reqLog, FILE_APPEND);
        } catch (\Throwable $e) { /* ignore logging errors */ }
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            try { file_put_contents(\Yii::getAlias('@app/runtime/curl_hatalari.txt'), $hataMesaji, FILE_APPEND | LOCK_EX); } catch (\Throwable $e) {}
            // Log RESPONSE (error)
            try {
                $logPrefix = '[' . date('Y-m-d H:i:s') . '] ';
                $resLog = $logPrefix . 'RESPONSE scf_carikart_listele carikodu=' . (string)$cariKartKodlari . ' cURL_ERROR=' . curl_error($curl) . "\n";
                file_put_contents(\Yii::getAlias('@app/runtime/dia_cari_listele_log.txt'), $resLog, FILE_APPEND);
            } catch (\Throwable $e) { }
            return null;
        } else {
            $json = json_decode($result, true);
            // Log RESPONSE (success)
            try {
                $logPrefix = '[' . date('Y-m-d H:i:s') . '] ';
                $resLog = $logPrefix . 'RESPONSE scf_carikart_listele carikodu=' . (string)$cariKartKodlari . ' body=' . $result . "\n";
                file_put_contents(\Yii::getAlias('@app/runtime/dia_cari_listele_log.txt'), $resLog, FILE_APPEND);
            } catch (\Throwable $e) { }
            return $json;
        }
        curl_close($curl);
    }
    public static function irsaliyeEkle($data = null)
    {
        $startTime = microtime(true);
        
        try {
            $url = self::getDiaUrl('scf');

            // If no data is provided, use default values
            if ($data === null) {
                $session_id = Dia::getsessionid();
                $firma_kodu = 1;
                $donem_kodu = 1;

                $data = [
                    "scf_irsaliye_ekle" => [
                        "session_id" => $session_id,
                        "firma_kodu" => $firma_kodu,
                        "donem_kodu" => $donem_kodu,
                        "kart" => [
                            "_key_ith_kart_ihr" => 0,
                            "_key_ith_kart_ith" => 0,
                            "_key_karsi_irsaliye" => 0,
                            "_key_krg_firma" => 0,
                            "_key_krg_gonderifisi" => 0,
                            "_key_muh_masrafmerkezi" => 0,
                            "_key_prj_proje" => ["kodu" => "000006"],
                            "_key_satiselemanlari" => [],
                            "_key_scf_carikart" => ["carikartkodu" => "0000008"],
                            "_key_scf_carikart_adresleri" => 178718,
                            "_key_scf_fatura" => 0,
                            "_key_scf_odeme_plani" => ["kodu" => "000008"],
                            "_key_scf_satiselemani" => 0,
                            "_key_scf_sevkaraci" => 0,
                            "_key_sis_depo_dest" => 0,
                            "_key_sis_depo_source" => ["depokodu" => "DEPO001"],
                            "_key_sis_devir" => 0,
                            "_key_sis_doviz" => ["adi" => "TL"],
                            "_key_sis_doviz_raporlama" => ["adi" => "TL"],
                            "_key_sis_firma_dest" => 0,
                            "_key_sis_ozelkod1" => 0,
                            "_key_sis_ozelkod2" => 0,
                            "_key_sis_seviyekodu" => 0,
                            "_key_sis_sube_dest" => 0,
                            "_key_sis_sube_source" => ["subekodu" => "SUBE001"],
                            "aciklama1" => "",
                            "aciklama2" => "",
                            "aciklama3" => "",
                            "bagkur" => "0.000000",
                            "bagkurdvz" => "0.000000",
                            "bagkuryuzde" => "0.000000",
                            "belgeno" => "000009",
                            "belgeno2" => "WS000001",
                            "borsa" => "0.000000",
                            "borsadvz" => "0.000000",
                            "borsayuzde" => "0.000000",
                            "dovizkuru" => "1.000000",
                            "ekalan1" => "",
                            "ekmaliyet" => "0.000000",
                            "fisno" => "WS00001",
                            "iptal" => "-",
                            "iptalnedeni" => "",
                            "istemcitipi" => "G",
                            "ithtipi" => "0",
                            "kargogonderimtarihi" => null,
                            "karsifirma" => "C",
                            "kdvduzenorani" => "+",
                            "kdvduzentutari" => "0.000000",
                            "kdvtebligi85" => "f",
                            "kilitli" => "f",
                            "kurguncelleme" => "",
                            "m_kalemler" => [[
                                "_key_kalemturu" => 177417,
                                "_key_muh_masrafmerkezi" => 0,
                                "_key_prj_proje" => ["kodu" => "000006"],
                                "_key_scf_fiyatkart" => 0,
                                "_key_scf_irsaliye_kalemi_iade" => 0,
                                "_key_scf_irsaliye_kalemi_oncekidonem" => 0,
                                "_key_scf_kalem_birimleri" => 177418,
                                "_key_scf_karsi_irsaliye_kalemi" => 0,
                                "_key_scf_odeme_plani" => 0,
                                "_key_scf_promosyon" => 0,
                                "_key_scf_satiselemani" => 0,
                                "_key_scf_siparis_kalemi" => 0,
                                "_key_sis_depo_dest" => 0,
                                "_key_sis_depo_source" => ["depokodu" => "DEPO001"],
                                "_key_sis_doviz" => ["adi" => "TL"],
                                "_key_sis_ozelkod" => 0,
                                "anamiktar" => "6.000000",
                                "birimfiyati" => "658.000000",
                                "dovizkuru" => "1.000000",
                                "irstarih" => "2024-05-10",
                                "kalemturu" => "MLZM",
                                "kdv" => "18.000000",
                                "kdvdurumu" => "H",
                                "kdvtevkifatorani" => "0",
                                "kdvtevkifattutari" => "0.000000",
                                "kdvtutari" => "710.640000",
                                "miktar" => "6.000000",
                                "note" => "",
                                "note2" => "",
                                "ovkdvoran" => "E",
                                "ovkdvtutar" => "E",
                                "ovmanuel" => "H",
                                "ozelalanf" => "",
                                "promosyonkalemid" => "",
                                "sirano" => 10,
                                "sonbirimfiyati" => "658.000000",
                                "tutari" => "3948.000000",
                                "yerelbirimfiyati" => "658.000000",
                                "m_varyantlar" => []
                            ]],
                            "navlun" => "0.000000",
                            "navlundvz" => "0.000000",
                            "navlunkdv" => "0.000000",
                            "navlunkdvdvz" => "0.000000",
                            "navlunkdvyuzde" => "0.000000",
                            "net" => "4658.640000",
                            "netdvz" => "4658.640000",
                            "ortalamavade" => "2024-09-07",
                            "raporlamadovizkuru" => "1.000000",
                            "saat" => "15:01:51",
                            "sevkadresi1" => "YILDIRIMÖNÜ MAH. ÇAMDALI SOK. NO:118",
                            "sevkadresi2" => "",
                            "sevkadresi3" => "Keçiören ANKARA",
                            "ssdf" => "0.000000",
                            "tarih" => "2024-05-10",
                            "toplam" => "3948.000000",
                            "toplamdvz" => "3948.000000",
                            "toplamkdv" => "710.640000",
                            "toplamkdvdvz" => "710.640000",
                            "toplamov" => "0.000000",
                            "toplamovdvz" => "0.000000",
                            "turu" => 1
                        ]
                    ]
                ];
            }
            
            // Encode the data - whether it's the default or provided data
            $jsonData = json_encode($data);
            
            if ($jsonData === false) {
                $errorLogFile = Yii::getAlias('@app/runtime/dia_irsaliye_errors_' . date('Y_m_d') . '.txt');
                $errorMessage = date('Y-m-d H:i:s') . " - JSON ENCODE HATASI: " . json_last_error_msg() . "\n";
                file_put_contents($errorLogFile, $errorMessage, FILE_APPEND | LOCK_EX);
                return null;
            }

            $curl = curl_init();
            
            curl_setopt($curl, CURLOPT_URL, $url);
            curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
            curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
            curl_setopt($curl, CURLOPT_HTTPHEADER, [
                'Content-Type: application/json',
                'Content-Length: ' . strlen($jsonData)
            ]);
            curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($curl, CURLOPT_TIMEOUT, 30);
            curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 10);
            
            $result = curl_exec($curl);
            $requestTime = microtime(true) - $startTime;
            
            // Detaylı curl bilgileri al
            $curlInfo = curl_getinfo($curl);
            $curlError = curl_error($curl);
            $curlErrno = curl_errno($curl);
            
            if (curl_errno($curl)) {
                $error = curl_error($curl);
                $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
                
                curl_close($curl);
                
                // Sadece hata durumlarında log dosyasına yaz
                $errorLogFile = Yii::getAlias('@app/runtime/dia_irsaliye_errors_' . date('Y_m_d') . '.txt');
                $errorMessage = date('Y-m-d H:i:s') . " - CURL HATASI: $error - HTTP: $httpCode\n";
                file_put_contents($errorLogFile, $errorMessage, FILE_APPEND | LOCK_EX);
                
                $hataMesaji = 'cURL hatası: ' . $error . ' - ' . date('Y-m-d H:i:s') . ' - HTTP: ' . $httpCode . PHP_EOL;
                file_put_contents(Yii::getAlias('@app/runtime/curl_hatalari.txt'), $hataMesaji, FILE_APPEND | LOCK_EX);
                
                return null;
            } else {
                $httpCode = curl_getinfo($curl, CURLINFO_HTTP_CODE);
                
                curl_close($curl);
                
                $json = json_decode($result, true);
                
                if ($json === null && json_last_error() !== JSON_ERROR_NONE) {
                    $errorLogFile = Yii::getAlias('@app/runtime/dia_irsaliye_errors_' . date('Y_m_d') . '.txt');
                    $errorMessage = date('Y-m-d H:i:s') . " - JSON DECODE HATASI: " . json_last_error_msg() . " - Response: " . substr($result, 0, 500) . "\n";
                    file_put_contents($errorLogFile, $errorMessage, FILE_APPEND | LOCK_EX);
                    
                    return null;
                }
                
                // Sadece hata durumlarında log dosyasına yaz
                $isSuccess = false;
                if (is_array($json)) {
                    // code 200 veya success true ise başarılı
                    if ((isset($json['code']) && ($json['code'] == '200' || $json['code'] == 200)) || 
                        (isset($json['success']) && $json['success'])) {
                        $isSuccess = true;
                    }
                }
                
                if (!$isSuccess) {
                    $resultLogFile = Yii::getAlias('@app/runtime/irsaliye_basarisiz_' . date('Y_m_d') . '.txt');
                    $resultLogMessage = date('Y-m-d H:i:s') . " - ";
                    if (isset($data['scf_irsaliye_ekle']['kart']['belgeno'])) {
                        $resultLogMessage .= "Belge: " . $data['scf_irsaliye_ekle']['kart']['belgeno'] . " - ";
                    }
                    $resultLogMessage .= "Result: " . json_encode($json) . "\n";
                    file_put_contents($resultLogFile, $resultLogMessage, FILE_APPEND | LOCK_EX);
                }
                
                return $json;
            }
            
        } catch (\Exception $e) {
            $errorLogFile = Yii::getAlias('@app/runtime/dia_irsaliye_errors_' . date('Y_m_d') . '.txt');
            $errorMessage = date('Y-m-d H:i:s') . " - DIA COMPONENT EXCEPTION: " . $e->getMessage() . " - File: " . $e->getFile() . " - Line: " . $e->getLine() . "\n";
            file_put_contents($errorLogFile, $errorMessage, FILE_APPEND | LOCK_EX);
            
            return null;
        }
    }
    public static function subeDepolarGetir(){
        $url = self::getDiaUrl('sis');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "sis_yetkili_firma_donem_sube_depo" => [
                "session_id" => $session_id,
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        $result = PythonDictConverter::toJson($result);
        // Hata kontrolü ekleyelim
        if (curl_errno($curl)) {
            $error = curl_error($curl);
            curl_close($curl);
            Yii::error("cURL error: $error", __METHOD__);
            return ['error' => $error];
        }
        curl_close($curl);
        
        // Ham sonucu loglayalım
        Yii::info("Raw API response: $result", __METHOD__);
        
        // PythonDictConverter'ı kaldırıp doğrudan JSON decode edelim
        try {
            return json_decode($result, true);
        } catch (\Exception $e) {
            Yii::error("JSON decode error: " . $e->getMessage(), __METHOD__);
            return null;
        }
    }
    //ürünün depolardaki miktarlarını getirir
    public static function depoMiktarlariListele($urun_key){
        $url = self::getDiaUrl('scf');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_stok_depo_miktarlari_listele" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "params" => [
                    "_key" => $urun_key,
                ]
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        $result = PythonDictConverter::toJson($result);
        // Hata kontrolü ekleyelim
        if (curl_errno($curl)) {
            $error = curl_error($curl);
            curl_close($curl);
            Yii::error("cURL error: $error", __METHOD__);
            return ['error' => $error];
        }
        curl_close($curl);
        
        // Ham sonucu loglayalım
        Yii::info("Raw API response: $result", __METHOD__);
        
        // PythonDictConverter'ı kaldırıp doğrudan JSON decode edelim
        try {
            return json_decode($result, true);
        } catch (\Exception $e) {
            Yii::error("JSON decode error: " . $e->getMessage(), __METHOD__);
            return null;
        }
    }
     //ürünün depolardaki miktarlarını getirir
    public static function stokkartHareketListele($urun_key){
        $url = self::getDiaUrl('scf');

        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_stokkart_hareket_listele" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "params" => [
                    "_key" => $urun_key,
                ]
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        $result = PythonDictConverter::toJson($result);
    
        // Hata kontrolü ekleyelim
        if (curl_errno($curl)) {
            $error = curl_error($curl);
            curl_close($curl);
            Yii::error("cURL error: $error", __METHOD__);
            return ['error' => $error];
        }
        curl_close($curl);
        
        // Ham sonucu loglayalım
        Yii::info("Raw API response: $result", __METHOD__);
        
        // PythonDictConverter'ı kaldırıp doğrudan JSON decode edelim
        try {
            return json_decode($result, true);
        } catch (\Exception $e) {
            Yii::error("JSON decode error: " . $e->getMessage(), __METHOD__);
            return null;
        }
    }
    public static function getSatiscilar(){
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_satiselemani_listele" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu
            ]
        ];

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            return null;
        } else {
            $json = json_decode($result, true);
            return $json;
        }
        curl_close($curl);      
    }
    public static function faturaListele($startDate = null,$endDate = null,$raw=false){
        if($startDate==null){
            $startDate = date('Y-m-d', strtotime('-1 day'));
        }
        if($endDate==null){
            $endDate = date('Y-m-d');
        }
        
        // Tarih formatını basitleştir - direkt string olarak kullan
        $startDateFormatted = $startDate;
        $endDateFormatted = $endDate;
        
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;

        $data = [
            "scf_fatura_listele" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" => [
                    ["field" => "tarih", "operator" => ">=", "value" => $startDateFormatted],
                    ["field" => "tarih", "operator" => "<=", "value" => $endDateFormatted],
                    ["field" => "turu", "operator" => "IN", "value" => "1,2,3"]
                ],
                "sorts" => "",
                "params" => "",
                "offset" => 0,
                "limit" => 30000,
            ]
        ];

        // Sade JSON log için tek dosya
        $logFile = Yii::getAlias('@app/runtime/dia_api.log');

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        // Timeout ayarları ekle
        curl_setopt($curl, CURLOPT_TIMEOUT, 180); // 3 dakika
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 45); // 45 saniye bağlantı timeout
        // TCP keepalive (varsa)
        if (defined('CURLOPT_TCP_KEEPALIVE')) {
            curl_setopt($curl, CURLOPT_TCP_KEEPALIVE, 1);
            curl_setopt($curl, CURLOPT_TCP_KEEPIDLE, 20);
            curl_setopt($curl, CURLOPT_TCP_KEEPINTVL, 15);
        }
        // Debug amaçlı verbose log
        $verboseFile = fopen(Yii::getAlias('@app/runtime/dia_curl_verbose.log'), 'a');
        curl_setopt($curl, CURLOPT_VERBOSE, true);
        curl_setopt($curl, CURLOPT_STDERR, $verboseFile);

        $execStart = microtime(true);
        $result = curl_exec($curl);
        $execEnd = microtime(true);
        $duration = round($execEnd - $execStart, 3);
        $info = curl_getinfo($curl);
        $httpCode = isset($info['http_code']) ? $info['http_code'] : 0;
        $transportInfoPath = Yii::getAlias('@app/runtime/dia_curl_info_fatura.txt');
        @file_put_contents($transportInfoPath, json_encode([
            'ts' => date('c'),
            'op' => 'faturaListele',
            'http' => $httpCode,
            'info' => $info,
            'request' => $data,
            'duration' => $duration
        ], JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);

        if (curl_errno($curl)) {
            $errorMsg = curl_error($curl);
            $logRow = [
                'ts' => date('c'),
                'op' => 'faturaListele',
                'start' => $startDate,
                'end' => $endDate,
                'http' => $httpCode,
                'dur_ms' => (int)round($duration * 1000),
                'status' => 'error',
                'count' => null,
                'error' => $errorMsg,
            ];
            @file_put_contents($logFile, json_encode($logRow, JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);
            if (is_resource($verboseFile)) { fclose($verboseFile); }
            curl_close($curl);
            return null;
        } else {
            // Cevabı ham olarak da kaydet (güvenlik için ilk 4KB)
            $rawPath = Yii::getAlias('@app/runtime/dia_fatura_raw.txt');
            @file_put_contents($rawPath, json_encode([
                'ts' => date('c'), 'http' => $httpCode, 'dur_ms' => (int)round($duration*1000), 'body_snippet' => substr((string)$result, 0, 4096)
            ], JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);

            $decoded = json_decode($result, true);
            $count = null;
            $status = 'ok';
            if (is_array($decoded) && isset($decoded['result']) && is_array($decoded['result'])) {
                $count = count($decoded['result']);
                if ($count === 0) {
                    $status = 'empty';
                }
            } elseif (is_array($decoded)) {
                $count = count($decoded);
            } else {
                $status = 'error';
            }
            $logRow = [
                'ts' => date('c'),
                'op' => 'faturaListele',
                'start' => $startDate,
                'end' => $endDate,
                'http' => $httpCode,
                'dur_ms' => (int)round($duration * 1000),
                'status' => $status,
                'count' => $count,
                'error' => null,
            ];
            @file_put_contents($logFile, json_encode($logRow, JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);
            if (is_resource($verboseFile)) { fclose($verboseFile); }
            curl_close($curl);
            if ($raw) {
                if (empty($decoded['result'])) {
                    return false;
                }
                return $result;
            }
            return $decoded["result"] ?? null;
        }
    }
    public static function faturaListeleayrintili($startDate,$endDate, $raw=false){
        if($startDate==null){
            $startDate = date('Y-m-d', strtotime('-1 day'));
        }
        if($endDate==null){
            $endDate = date('Y-m-d');
        }
        
        // Tarih formatını basitleştir - direkt string olarak kullan
        $startDateFormatted = $startDate;
        $endDateFormatted = $endDate;
        
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();
        $firma_kodu = 1;
        $donem_kodu = 1;
 
        $data = [
            "scf_fatura_listele_ayrintili" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "filters" => [
                    ["field" => "tarih", "operator" => ">=", "value" => $startDateFormatted],
                    ["field" => "tarih", "operator" => "<=", "value" => $endDateFormatted],
                    ["field" => "turu", "operator" => "IN", "value" => "1,2,3"]
                ],
                "sorts" => "",
                "params" => "",
                "offset" => 0,
                "limit" => 30000,
            ]
        ];

        // Sade JSON log için tek dosya
        $logFile = Yii::getAlias('@app/runtime/dia_api.log');

        $jsonData = json_encode($data);
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
        // Timeout ayarları ekle
        curl_setopt($curl, CURLOPT_TIMEOUT, 120); // 2 dakika
        curl_setopt($curl, CURLOPT_CONNECTTIMEOUT, 30); // 30 saniye bağlantı timeout
        if (defined('CURLOPT_TCP_KEEPALIVE')) {
            curl_setopt($curl, CURLOPT_TCP_KEEPALIVE, 1);
            curl_setopt($curl, CURLOPT_TCP_KEEPIDLE, 20);
            curl_setopt($curl, CURLOPT_TCP_KEEPINTVL, 15);
        }
        $verboseFile = fopen(Yii::getAlias('@app/runtime/dia_curl_verbose.log'), 'a');
        curl_setopt($curl, CURLOPT_VERBOSE, true);
        curl_setopt($curl, CURLOPT_STDERR, $verboseFile);

        $execStart = microtime(true);
        $result = curl_exec($curl);
        $execEnd = microtime(true);
        $duration = round($execEnd - $execStart, 3);
        $info = curl_getinfo($curl);
        $httpCode = isset($info['http_code']) ? $info['http_code'] : 0;
        $transportInfoPath = Yii::getAlias('@app/runtime/dia_curl_info_fatura_kalem.txt');
        @file_put_contents($transportInfoPath, json_encode([
            'ts' => date('c'),
            'op' => 'faturaListeleAyrintili',
            'http' => $httpCode,
            'info' => $info,
            'request' => $data,
            'duration' => $duration
        ], JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);

        if (curl_errno($curl)) {
            $error = curl_error($curl);
            $logRow = [
                'ts' => date('c'),
                'op' => 'faturaListeleAyrintili',
                'start' => $startDate,
                'end' => $endDate,
                'http' => $httpCode,
                'dur_ms' => (int)round($duration * 1000),
                'status' => 'error',
                'count' => null,
                'error' => $error,
            ];
            @file_put_contents($logFile, json_encode($logRow, JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);
            if (is_resource($verboseFile)) { fclose($verboseFile); }
            curl_close($curl);
            return null;
        } else {
            $rawPath = Yii::getAlias('@app/runtime/dia_fatura_kalem_raw.txt');
            @file_put_contents($rawPath, json_encode([
                'ts' => date('c'), 'http' => $httpCode, 'dur_ms' => (int)round($duration*1000), 'body_snippet' => substr((string)$result, 0, 4096)
            ], JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);

            $decoded = json_decode($result, true);
            $count = null;
            $status = 'ok';
            if (is_array($decoded) && isset($decoded['result']) && is_array($decoded['result'])) {
                $count = count($decoded['result']);
                if ($count === 0) {
                    $status = 'empty';
                }
            } elseif (is_array($decoded)) {
                $count = count($decoded);
            } else {
                $status = 'error';
            }
            $logRow = [
                'ts' => date('c'),
                'op' => 'faturaListeleAyrintili',
                'start' => $startDate,
                'end' => $endDate,
                'http' => $httpCode,
                'dur_ms' => (int)round($duration * 1000),
                'status' => $status,
                'count' => $count,
                'error' => null,
            ];
            @file_put_contents($logFile, json_encode($logRow, JSON_UNESCAPED_UNICODE) . PHP_EOL, FILE_APPEND | LOCK_EX);
            if (is_resource($verboseFile)) { fclose($verboseFile); }
            curl_close($curl);
            if ($raw) {
                if (empty($decoded['result'])) {
                    return false;
                }
                return $result;
            }
            return $decoded["result"] ?? null; 
        }
    }
    public static function siparisgonder($fis,$tur=1){
        $logFile = Yii::getAlias('@runtime') . '/siparisgonder_log_' . date('Ymd_His') . '.txt';
        $logContent = '';
        $logContent .= "[".date('Y-m-d H:i:s')."] Siparisgonder başladı - Fis ID: {$fis->id}, Tur: $tur\n";
        
        $url = self::getDiaUrl('scf');
        $logContent .= "[".date('Y-m-d H:i:s')."] API URL: $url\n";
        
        $session_id = Dia::getsessionid();
        $logContent .= "[".date('Y-m-d H:i:s')."] Session ID alındı: $session_id\n";
        
        $firma_kodu = 1;
        $donem_kodu = 1;
        
        if($tur==1)          
            $satirlar=$fis->getSatinAlmaSiparisFisSatirs()->with('urun')->all();
        else 
            $satirlar=$fis->getSatissatirlari()->all();
        
        $branchCode= Warehouses::find()->select(["branch_code"])->where(["warehouse_code" => $fis->satinalmasiparisfis->warehouse_code])->scalar();        
        $logContent .= "[".date('Y-m-d H:i:s')."] Satır sayısı: " . count($satirlar) . "\n";
        
        $sira=1;
        $kalemler = [];
        foreach ($satirlar as $satir) {
            $logContent .= "[".date('Y-m-d H:i:s')."] Satır $sira işleniyor...\n";
            
            $sd=[];
            $stok = null;
            $birimAlani = null;
            $stno=$satir->StokKodu;

            $logContent .= "[".date('Y-m-d H:i:s')."] Stok No: $stno\n";

            if ($satir instanceof \app\models\SatinAlmaSiparisFisSatir) { // Satınalma sipariş satırı ise
                if (!$satir->urun) {
                    $logContent .= "[".date('Y-m-d H:i:s')."] UYARI: Satır $sira için ürün bulunamadı, atlanıyor\n";
                    continue; // İlişkili ürün yoksa atla
                }
                $stok = $satir->urun;
                $birimAlani = $satir->birim; // birim alanı kullanılıyor
                $logContent .= "[".date('Y-m-d H:i:s')."] Ürün bulundu: {$stok->StokKodu}, Birim: $birimAlani\n";
            } else { // Satış sipariş satırı ise (varsayılan)
                $stok = Urunler::find()->where(["StokKodu" =>$stno ])->one();
                if (!$stok) {
                    $logContent .= "[".date('Y-m-d H:i:s')."] UYARI: Stok kodu $stno için ürün bulunamadı, atlanıyor\n";
                    continue;
                }
                $birimAlani = $satir->BirimTipi; // BirimTipi alanı olduğu varsayılıyor
                $logContent .= "[".date('Y-m-d H:i:s')."] Ürün bulundu: {$stok->StokKodu}, Birim: $birimAlani\n";
            }

            // Birim-key seçimi: normalize et, güvenli varsayılan uygula, tanımsız kalmasını engelle
            $birimkey = null;
            $birimAlaniNormalized = strtoupper(trim((string)$birimAlani));
            if ($birimAlaniNormalized === 'UNIT') {
                $birimkey = $stok->BirimKey1;
                $logContent .= "[".date('Y-m-d H:i:s')."] Birim=UNIT, BirimKey1 kullanılacak: {$stok->BirimKey1}\n";
            } elseif ($birimAlaniNormalized === 'BOX') {
                $birimkey = $stok->BirimKey2 ?: $stok->BirimKey1;
                $logContent .= "[".date('Y-m-d H:i:s')."] Birim=BOX, BirimKey2 yoksa BirimKey1: {$birimkey}\n";
            } elseif ($birimAlaniNormalized === 'PACK') {
                // PACK için varsa BirimKey3, yoksa 2, o da yoksa 1
                $birimkey = $stok->BirimKey3 ?: ($stok->BirimKey2 ?: $stok->BirimKey1);
                $logContent .= "[".date('Y-m-d H:i:s')."] Birim=PACK, BirimKey3/2/1 sırasıyla: {$birimkey}\n";
            } else {
                // Boş/bilinmeyen birim: ana birime (BirimKey1) düş, yoksa 2/3
                $birimkey = $stok->BirimKey1 ?: ($stok->BirimKey2 ?: $stok->BirimKey3);
                $logContent .= "[".date('Y-m-d H:i:s')."] Birim boş/bilinmiyor ('{$birimAlani}'), varsayılan birim seçildi: {$birimkey}\n";
            }

            if (empty($birimkey)) {
                $logContent .= "[".date('Y-m-d H:i:s')."] HATA: Geçerli BirimKey bulunamadı (StokKodu: {$stok->StokKodu}). Gönderim iptal.\n";
                file_put_contents($logFile, $logContent);
                return 0;
            }

            $logContent .= "[".date('Y-m-d H:i:s')."] Birim Key (seçilen): $birimkey\n";

            $satirtutari=0;//$satir->BirimFiyat*$satir->Miktar*(1-$satir->Iskonto/100);
            $satirkdv=0;//$satirtutari*$satir->vat/100;
            /*
        sd de 
               
        */
            $sd=[
                "_key_kalemturu" => ["stokkartkodu" => $stno],
                "_key_scf_kalem_birimleri" => (int)$birimkey,
                 "_key_sis_depo_source" => ["depokodu" => $fis->satinalmasiparisfis->warehouse_code],
                "_key_sis_doviz" => ["adi" => "GBP"],
                "anamiktar" => number_format($satir->miktar ?? 0, 6, '.', ''),
                "birimfiyati" => number_format($satir->BirimFiyat??0, 6, '.', ''),
                "daraadet" => "0.000000",
                "dovizkuru" => "1.000000",
                "indirim1" => "0.000000",
                "indirim2" => "0.000000",
                "indirim3" => "0.000000",
                "indirim4" => "0.000000",
                "indirim5" => "0.000000",
                "indirimtoplam" => "0.000000",
                "indirimtutari" => number_format($satir->retro ?? 0, 6, '.', ''),
                "kalemturu" => "MLZM",
                "kdv" => number_format($stok->Vat ?? 0, 6, '.', ''),
                "kdvdurumu" => "H",
                "kdvtutari" => number_format($satirkdv, 6, '.', ''),
                "miktar" => number_format($satir->miktar ?? 0, 6, '.', ''),
                "note" => "",
                "note2" => "",
                "onay" => "KABUL",
                "rezervasyon" => "H",
                "siptarih" => $fis->satinalmasiparisfis->tarih,
                "sirano" => $sira,
                "sonbirimfiyati" => number_format($satir->BirimFiyat??0, 6, '.', ''),
                "teslimattarihi" => null,
                "tutari" => number_format($satirtutari, 6, '.', ''),
                "yerelbirimfiyati" => number_format($satir->BirimFiyat??0, 6, '.', ''),
                "m_varyantlar" => []
            ];
            $kalemler[]=$sd;
            $logContent .= "[".date('Y-m-d H:i:s')."] Satır $sira kalem array'e eklendi\n";
            $sira++;
        }
        
        $logContent .= "[".date('Y-m-d H:i:s')."] Tedarikci kodu: {$fis->tedarikci->tedarikci_kodu}\n";
        $logContent .= "[".date('Y-m-d H:i:s')."] Fisno: {$fis->fisno}\n";
        $logContent .= "[".date('Y-m-d H:i:s')."] Tarih: {$fis->satinalmasiparisfis->tarih}\n";
        /*
        data da  "_key_sis_depo_source" => ["depokodu" => "44.03.01"], iptal edildi
         "_key_krg_firma" => 183509,
          "_key_scf_carikart_adresleri" => 178718,
        */
        $data = [
            "scf_siparis_ekle" => [
                "session_id" => $session_id,
                "firma_kodu" => 1,
                "donem_kodu" => 1,
                "kart" => [
                    "_key_sis_sube_source" => ["subekodu" => $branchCode],
                    "_key_scf_carikart" => ["carikartkodu" =>$fis->tedarikci->tedarikci_kodu],
                    "_key_sis_depo_source" => ["depokodu" => $fis->satinalmasiparisfis->warehouse_code],

                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                    "_key_sis_ozelkod1" => 0,
                    "_key_sis_ozelkod2" => 0,
                    "_key_sis_sube_source" => ["subekodu" => (string)$branchCode],
                    "aciklama1" => "",
                    "aciklama2" => "",
                    "aciklama3" => "",
                    "belgeno" => "",
                    "dovizkuru" => "1.000000",
                    "ekalan1" => "",
                    "fisno" => $fis->fisno,
                    "m_kalemler" => $kalemler,
                    "net" => "0.000000",
                    "netdvz" => "0.000000",
                    "odemeislemli" => "f",
                    "odemeli" => "f",
                    "onay" => "KABUL",
                    "ortalamavade" => $fis->satinalmasiparisfis->tarih,
                    "raporlamadovizkuru" => "1.000000",
                    "saat" => date("H:i:s"),
                    "tarih" => date("Y-m-d"),
                    "teslimat_adres1" => "",
                    "teslimat_adres2" => "",
                    "teslimat_adsoyad" => "",
                    "teslimat_ceptel" => "",
                    "teslimat_ilce" => "",
                    "teslimat_key_sis_sehirler" => 0,
                    "teslimat_telefon" => "",
                    "toplam" => "00.000000",
                    "toplamdvz" => "0.000000",
                    "toplamindirim" => "0.000000",
                    "toplamindirimdvz" => "0.000000",
                    "toplamkdv" => "0.000000",
                    "toplamkdvdvz" => "0.000000",
                    "toplammasraf" => "0.000000",
                    "toplammasrafdvz" => "0.000000",
                    "turu" => 1
                ]
            ]
        ];
        
        $jsonData = json_encode($data);
        $logContent .= "[".date('Y-m-d H:i:s')."] GÖNDERILEN JSON DATA:\n" . $jsonData . "\n";
        $logContent .= "[".date('Y-m-d H:i:s')."] JSON DATA (Pretty Print):\n" . json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE) . "\n";
        
       // echo $jsonData;
        // cURL başlat
        $logContent .= "[".date('Y-m-d H:i:s')."] cURL başlatılıyor...\n";
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL,  $url); // Burada $newUrl kullanıyoruz
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false); // Sertifika doğrulamasını kapatıyoruz (test amaçlı)
        
        $logContent .= "[".date('Y-m-d H:i:s')."] cURL isteği gönderiliyor...\n";
        $result = curl_exec($curl);
        $logContent .= "[".date('Y-m-d H:i:s')."] cURL isteği tamamlandı\n";
        
        print_r($result);
        // Eğer cURL hatası varsa yazdır
        $logContent .= "[".date('Y-m-d H:i:s')."] API Response: " . $result . "\n";
        if (curl_errno($curl)) {
            $hataMesaji = 'cURL hatası: ' . curl_error($curl) . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
           $sonuc=0;
            $errorMsg = 'cURL hatası: ' . curl_error($curl);
            $logContent .= "[".date('Y-m-d H:i:s')."] ERROR: $errorMsg\n";
            file_put_contents($logFile, $logContent);
            curl_close($curl);
            return 0;
        } else {
            $json = json_decode($result, true);
            $logContent .= "[".date('Y-m-d H:i:s')."] JSON Decode: " . print_r($json, true) . "\n";
            
            // API response'unda hata kontrolü yap
            if (isset($json['code']) && $json['code'] != '200' && $json['code'] != 200) {
                $errorMsg = isset($json['msg']) ? $json['msg'] : 'Bilinmeyen API hatası';
                $logContent .= "[".date('Y-m-d H:i:s')."] API HATASI: Code: {$json['code']}, Message: $errorMsg\n";
                $logContent .= "[".date('Y-m-d H:i:s')."] Siparisgonder başarısız - Return: 0\n";
                file_put_contents($logFile, $logContent);
                curl_close($curl);
                return 0;
            }
            
            $logContent .= "[".date('Y-m-d H:i:s')."] Fis Errors: " . print_r($fis->errors, true) . "\n";
            
            // API response'undan fisno'yu al
            $returnedFisno = null;
            if (isset($json['extra']['fisno'])) {
                $returnedFisno = $json['extra']['fisno'];
                $logContent .= "[".date('Y-m-d H:i:s')."] API'den dönen fisno: $returnedFisno\n";
            }
            
            $logContent .= "[".date('Y-m-d H:i:s')."] Siparisgonder başarılı - Return: " . ($returnedFisno ?: 1) . "\n";
            file_put_contents($logFile, $logContent);
            curl_close($curl);
            return $returnedFisno ?: 1;
        }
    }

    public static function goodReceiptIrsaliyeEkle($fis,$kalemler)
    {
        
        $url = self::getDiaUrl('scf');
        $session_id = Dia::getsessionid();

        $firma_kodu = 1;
        $donem_kodu = 1;
        
        $sira=0;
        $tumkalemler=[];
        
        // Depo key değerini belirle (sipariş varsa ondan al, yoksa warehouse'dan)
        $depo_key = null;
        if($fis->siparis && isset($fis->siparis->_key_sis_depo_source)) {
            $depo_key = $fis->siparis->_key_sis_depo_source;
        } elseif($fis->warehouse && isset($fis->warehouse->_key)) {
            $depo_key = $fis->warehouse->_key;
        }
        
        foreach($kalemler as $k){
            // urun_key kullan (veritabanında bu şekilde tanımlı)
            $urun=Urunler::find()->where(["_key"=>$k->urun_key])->one();
            $sira++;
            if($urun){
                $kalem= [
                    "_key_kalemturu" => $urun->_key, // DIA bu alanı zorunlu istiyor
                    "_key_scf_stokkart" => ["stokkodu" => $urun->StokKodu], // Stok kartı referansı
                    "_key_scf_kalem_birimleri" => $urun->BirimKey2,
                    "_key_sis_depo_source" => $depo_key,
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "anamiktar" => floatval($k->quantity_received),
                    "dovizkuru" => "1.000000",
                    "irstarih" => date("Y-m-d"),
                    "kalemturu" => "MLZM",
                    "miktar" => floatval($k->quantity_received),
                    "note" => "",
                    "note2" => "",
                    "ovkdvoran" => "E",
                    "ovkdvtutar" => "E",
                    "ovmanuel" => "H",
                    "ozelalanf" => "",
                    "promosyonkalemid" => "",
                    "sirano" => $sira
                ];
                
                // siparis_key varsa ekle
                if(!empty($k->siparis_key)) {
                    $kalem["_key_scf_siparis_kalemi"] = $k->siparis_key;
                }
                
                $kalem["m_varyantlar"] = [];
                $tumkalemler[] = $kalem; // $kalem tanımlı olduğundan emin olduktan sonra ekle
            }
        }
        
        // Cari kodu belirle
        $carikod = "C00000001";
        if($fis->siparis && isset($fis->siparis->__carikodu) && !empty($fis->siparis->__carikodu)) {
            $carikod = $fis->siparis->__carikodu;
        }
        
        $data = [
            "scf_irsaliye_ekle" => [
                "session_id" => $session_id,
                "firma_kodu" => $firma_kodu,
                "donem_kodu" => $donem_kodu,
                "kart" => [
                    "_key_scf_carikart" => ["carikartkodu" => $carikod],
                    "_key_sis_depo_source" => $fis->warehouse->_key,
                    "_key_sis_doviz" => ["adi" => "GBP"],
                    "_key_sis_doviz_raporlama" => ["adi" => "GBP"],
                    "_key_sis_sube_source" => $fis->warehouse->branch->_key,
                    "belgeno" => "000009",
                    "belgeno2" => "WS000001",
                    "dovizkuru" => "1.000000", // Duplicate kaldırıldı
                    "fisno" => "WS00001",
                    "karsifirma" => "C",
                    "m_kalemler" => $tumkalemler,
                    "raporlamadovizkuru" => "1.000000",
                    "saat" => date("H:i:s"),
                    "tarih" => date("Y-m-d"),
                    "turu" => 1
                ]
            ]
        ];


        $jsonData = json_encode($data);
        
        // Debug: Gönderilen veriyi logla
        Yii::info("DIA'ya gönderilen JSON: " . $jsonData, __METHOD__);
     
        $curl = curl_init();
        curl_setopt($curl, CURLOPT_URL, $url);
        curl_setopt($curl, CURLOPT_CUSTOMREQUEST, "POST");
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($curl, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($curl, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);

        $result = curl_exec($curl);

        if (curl_errno($curl)) {
            $error = curl_error($curl);
            curl_close($curl);
            $hataMesaji = 'cURL hatası: ' . $error . ' - ' . date('Y-m-d H:i:s') . PHP_EOL;
            file_put_contents('runtime/curl_hatalari.txt', $hataMesaji, FILE_APPEND | LOCK_EX);
            Yii::error("DIA cURL hatası: " . $error, __METHOD__);
            return null;
        } else {
            curl_close($curl);
            $json = json_decode($result, true);
            
            // Debug için DIA yanıtını logla
            Yii::info("DIA İrsaliye Ekleme Yanıtı: " . json_encode($json), __METHOD__);
            
            // Başarılı/başarısız durumu kontrol et
            if(isset($json['code'])) {
                if($json['code'] == '200') {
                    Yii::info("DIA İrsaliye başarıyla eklendi. Key: " . ($json['key'] ?? 'N/A'), __METHOD__);
                } else {
                    Yii::error("DIA İrsaliye eklenemedi. Hata: " . ($json['msg'] ?? 'Bilinmeyen hata'), __METHOD__);
                }
            }
            
            return $json;
        }
    }
}