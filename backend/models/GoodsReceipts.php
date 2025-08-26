<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "goods_receipts".
 *
 * @property int $goods_receipt_id
 * @property int $warehouse_id
 * @property int|null $siparis_id
 * @property string|null $invoice_number
 * @property string|null $delivery_note_number
 * @property int $employee_id
 * @property string $receipt_date
 * @property string|null $created_at
 * @property string|null $updated_at
 *
 * @property GoodsReceiptItems[] $goodsReceiptItems
 */
class GoodsReceipts extends \yii\db\ActiveRecord
{
    /**
     * {@inheritdoc}
     */
    public static function tableName()
    {
        return 'goods_receipts';
    }

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['warehouse_id', 'employee_id', 'receipt_date'], 'required'],
            [['warehouse_id', 'siparis_id', 'employee_id'], 'integer'],
            [['receipt_date', 'created_at', 'updated_at'], 'safe'],
            [['invoice_number', 'delivery_note_number'], 'string', 'max' => 255],
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function attributeLabels()
    {
        return [
            'goods_receipt_id' => 'Goods Receipt ID',
            'warehouse_id' => 'Warehouse ID',
            'siparis_id' => 'Siparis ID',
            'invoice_number' => 'Invoice Number',
            'delivery_note_number' => 'Delivery Note Number',
            'employee_id' => 'Employee ID',
            'receipt_date' => 'Receipt Date',
            'created_at' => 'Created At',
            'updated_at' => 'Updated At',
        ];
    }

    /**
     * Gets query for [[GoodsReceiptItems]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getGoodsReceiptItems()
    {
        return $this->hasMany(GoodsReceiptItems::class, ['receipt_id' => 'goods_receipt_id']);
    }
}