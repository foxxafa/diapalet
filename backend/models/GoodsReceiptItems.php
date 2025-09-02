<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "goods_receipt_items".
 *
 * @property int $id
 * @property int $receipt_id
 * @property string|null $urun_key
 * @property string|null $birim_key
 * @property float $quantity_received
 * @property string|null $pallet_barcode
 * @property string|null $barcode
 * @property string|null $expiry_date
 * @property string|null $created_at
 * @property string|null $updated_at
 * @property string|null $siparis_key
 * @property string|null $StokKodu
 *
 * @property GoodsReceipts $receipt
 * @property Urunler $urun
 */
class GoodsReceiptItems extends \yii\db\ActiveRecord
{


    /**
     * {@inheritdoc}
     */
    public static function tableName()
    {
        return 'goods_receipt_items';
    }

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['urun_key', 'birim_key', 'pallet_barcode', 'barcode', 'expiry_date', 'siparis_key', 'StokKodu'], 'default', 'value' => null],
            [['receipt_id', 'quantity_received'], 'required'],
            [['receipt_id'], 'integer'],
            [['quantity_received'], 'number'],
            [['expiry_date', 'created_at', 'updated_at'], 'safe'],
            [['urun_key', 'birim_key', 'siparis_key'], 'string', 'max' => 10],
            [['pallet_barcode', 'barcode', 'StokKodu'], 'string', 'max' => 50],
            [['receipt_id'], 'exist', 'skipOnError' => true, 'targetClass' => GoodsReceipts::class, 'targetAttribute' => ['receipt_id' => 'goods_receipt_id']],
            [['StokKodu'], 'exist', 'skipOnError' => true, 'targetClass' => Urunler::class, 'targetAttribute' => ['StokKodu' => 'StokKodu']],
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function attributeLabels()
    {
        return [
            'id' => 'ID',
            'receipt_id' => 'Receipt ID',
            'urun_key' => 'Urun Key',
            'birim_key' => 'Birim Key',
            'quantity_received' => 'Quantity Received',
            'pallet_barcode' => 'Pallet Barcode',
            'barcode' => 'Barcode',
            'expiry_date' => 'Expiry Date',
            'created_at' => 'Created At',
            'updated_at' => 'Updated At',
            'siparis_key' => 'Siparis Key',
            'StokKodu' => 'Stok Kodu',
        ];
    }

    /**
     * Gets query for [[Receipt]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getReceipt()
    {
        return $this->hasOne(GoodsReceipts::class, ['goods_receipt_id' => 'receipt_id']);
    }

    /**
     * Gets query for [[Urun]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getUrun()
    {
        return $this->hasOne(Urunler::class, ['StokKodu' => 'StokKodu']);
    }

}
