<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "goods_receipt_items".
 *
 * @property int $id
 * @property int $receipt_id
 * @property string|null $urun_key
 * @property float $quantity_received
 * @property string|null $pallet_barcode
 * @property string|null $expiry_date
 * @property string|null $created_at
 * @property string|null $updated_at
 * @property string|null $siparis_key
 *
 * @property GoodsReceipts $receipt
 * @property Urunler $urunKey
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
            [['urun_key', 'pallet_barcode', 'expiry_date', 'siparis_key'], 'default', 'value' => null],
            [['receipt_id', 'quantity_received'], 'required'],
            [['receipt_id'], 'integer'],
            [['quantity_received'], 'number'],
            [['expiry_date', 'created_at', 'updated_at'], 'safe'],
            [['urun_key', 'siparis_key'], 'string', 'max' => 10],
            [['pallet_barcode'], 'string', 'max' => 50],
            [['receipt_id'], 'exist', 'skipOnError' => true, 'targetClass' => GoodsReceipts::class, 'targetAttribute' => ['receipt_id' => 'goods_receipt_id']],
            [['urun_key'], 'exist', 'skipOnError' => true, 'targetClass' => Urunler::class, 'targetAttribute' => ['urun_key' => '_key']],
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
            'quantity_received' => 'Quantity Received',
            'pallet_barcode' => 'Pallet Barcode',
            'expiry_date' => 'Expiry Date',
            'created_at' => 'Created At',
            'updated_at' => 'Updated At',
            'siparis_key' => 'Siparis Key',
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
     * Gets query for [[UrunKey]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getUrunKey()
    {
        return $this->hasOne(Urunler::class, ['_key' => 'urun_key']);
    }

}
