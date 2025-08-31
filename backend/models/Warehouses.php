<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "warehouses".
 *
 * @property int $id
 * @property string|null $name
 * @property string|null $post_code
 * @property string|null $ap
 * @property string|null $branch_code
 * @property string|null $warehouse_code
 * @property string|null $_key
 */
class Warehouses extends \yii\db\ActiveRecord
{
    /**
     * {@inheritdoc}
     */
    public static function tableName()
    {
        return 'warehouses';
    }

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['name', 'post_code', 'ap', 'branch_code', 'warehouse_code', '_key'], 'default', 'value' => null],
            [['branch_code', '_key'], 'string'],
            [['name'], 'string', 'max' => 255],
            [['post_code'], 'string', 'max' => 10],
            [['ap'], 'string', 'max' => 1],
            [['warehouse_code'], 'string', 'max' => 15],
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function attributeLabels()
    {
        return [
            'id' => 'ID',
            'name' => 'Name',
            'post_code' => 'Post Code',
            'ap' => 'Ap',
            'branch_code' => 'Branch Code',
            'warehouse_code' => 'Warehouse Code',
            '_key' => 'Key',
        ];
    }

    /**
     * Gets query for [[Branch]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getBranch()
    {
        return $this->hasOne(Branches::class, ['branch_code' => 'branch_code']);
    }

    /**
     * Get warehouses list for dropdown
     * @return array
     */
    public static function getWarehouseList()
    {
        return \yii\helpers\ArrayHelper::map(self::find()->all(), 'warehouse_code', 'name');
    }

    /**
     * Get warehouses by branch code
     * @param string $branchCode
     * @return array
     */
    public static function getWarehousesByBranch($branchCode)
    {
        return \yii\helpers\ArrayHelper::map(
            self::find()->where(['branch_code' => $branchCode])->all(), 
            'warehouse_code', 
            'name'
        );
    }

}
