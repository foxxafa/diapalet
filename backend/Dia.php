<?php
namespace app\components;

use Yii;
use yii\base\Component;
use yii\base\InvalidConfigException;
use app\models\Satisfisleri;
use app\models\Satissatirlari;
use app\models\CashRegisters;
use app\models\CariHareketler;
use app\models\Musteriler;
use app\models\Urunler;
use app\models\SatinAlmaSiparisFisSatir;

class Dia extends Component{
    public static function test(){
        echo "tamam";
    }

    public static function getsessionid(){
        $url = "https://aytacfoods.ws.dia.com.tr/api/v3/sis/json";
        $data = [
            "login" => [
                "username" => "Ws-03",
                "password" => "Ws123456.",
                "disconnect_same_user" => "true",
                "lang" => "tr",
                "params" => [
                    "apikey" => "dbbd8cb8-846f-4379-8d77-505e845db4a2"
                ]
            ]
        ];

        $jsonData = json_encode($data);

        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $jsonData);
        curl_setopt($ch, CURLOPT_HTTPHEADER, [
            'Content-Type: application/json',
            'Content-Length: ' . strlen($jsonData)
        ]);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);

        $response = curl_exec($ch);

        if (curl_errno($ch)) {
            return null;
        }

        $data = json_decode($response, true);

        // "session" değerini al
        if (isset($data['msg'])) {
            return $data['msg'];
        }
        return null;
    }

    // --- BU DOSYADAKİ DİĞER TÜM FONKSİYONLAR ---
    // Not: Kodun geri kalanını, bu dosyanın çok uzun olmaması için eklemedim,
    // ama senin gönderdiğin orijinal dosyadaki tüm diğer fonksiyonlar
    // (stokbirimgetir, tahsilatgonder vb.) burada yer almalıdır.
    // Lütfen tam içeriği yapıştırdığından emin ol.

    public static function stokbirimgetir(){
        // ... Senin gönderdiğin tam kod ...
    }

    public static function tahsilatgonder($model){
        // ... Senin gönderdiğin tam kod ...
    }

    public static function numarailefisgonder($fisno){
        // ... Senin gönderdiğin tam kod ...
    }

    // ... ve diğer tüm fonksiyonlar ...
}
