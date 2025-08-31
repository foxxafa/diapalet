<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "shelfs".
 *
 * @property int $id
 * @property int|null $warehouse_id
 * @property string|null $name
 * @property string|null $code
 * @property string|null $dia_key
 * @property int|null $is_active
 * @property string|null $created_at
 * @property string|null $updated_at
 * @property int|null $sales_shelf
 *
 * @property InventoryStock[] $inventoryStocks
 * @property InventoryTransfers[] $inventoryTransfers
 * @property InventoryTransfers[] $inventoryTransfers0
 * @property Warehouses $warehouse
 */
class Shelfs extends \yii\db\ActiveRecord
{


    /**
     * {@inheritdoc}
     */
    public static function tableName()
    {
        return 'shelfs';
    }

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['warehouse_id', 'name', 'code', 'dia_key', 'warehouse_code'], 'default', 'value' => null],
            [['is_active'], 'default', 'value' => 1],
            [['sales_shelf'], 'default', 'value' => 0],
            [['warehouse_id', 'is_active', 'sales_shelf'], 'integer'],
            [['created_at', 'updated_at'], 'safe'],
            [['name', 'code', 'dia_key'], 'string', 'max' => 20],
            [['warehouse_code'], 'string', 'max' => 20],
            [['warehouse_id'], 'exist', 'skipOnError' => true, 'targetClass' => Warehouses::class, 'targetAttribute' => ['warehouse_id' => 'id']],
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function attributeLabels()
    {
        return [
            'id' => 'ID',
            'warehouse_id' => 'Warehouse ID',
            'name' => 'Name',
            'code' => 'Code',
            'dia_key' => 'Dia Key',
            'is_active' => 'Is Active',
            'sales_shelf' => 'Sales Shelf',
            'created_at' => 'Created At',
            'updated_at' => 'Updated At',
            'warehouse_code' => 'Warehouse Code',
        ];
    }

    /**
     * Gets query for [[InventoryStocks]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getInventoryStocks()
    {
        return $this->hasMany(InventoryStock::class, ['location_id' => 'id']);
    }

    /**
     * Gets query for [[InventoryTransfers]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getInventoryTransfers()
    {
        return $this->hasMany(InventoryTransfers::class, ['from_location_id' => 'id']);
    }

    /**
     * Gets query for [[InventoryTransfers0]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getInventoryTransfers0()
    {
        return $this->hasMany(InventoryTransfers::class, ['to_location_id' => 'id']);
    }

    /**
     * Gets query for [[Warehouse]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getWarehouse()
    {
        return $this->hasOne(Warehouses::class, ['id' => 'warehouse_id']);
    }

}
