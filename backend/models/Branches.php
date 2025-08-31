<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "branches".
 *
 * @property int $id
 * @property string $name
 * @property string|null $address
 * @property string|null $description
 * @property float|null $latitude
 * @property float|null $longitude
 * @property int $is_active
 * @property string|null $created_at
 * @property string|null $updated_at
 * @property string|null $post_code
 * @property string|null $parent_code
 * @property CashRegisters[] $cashRegisters
 */
class Branches extends \yii\db\ActiveRecord
{
    const STATUS_INACTIVE = 0;
    const STATUS_ACTIVE = 1;

    /**
     * {@inheritdoc}
     */
    public static function tableName()
    {
        return 'branches';
    }

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['name'], 'required'],
            [['description', 'post_code', 'parent_code', 'branch_code', '_key'], 'string'],
            [['is_active'], 'integer'],
            [['is_active'], 'default', 'value' => 1],
            [['latitude', 'longitude'], 'number'],
            [['created_at', 'updated_at'], 'safe'],
            [['name'], 'string', 'max' => 100],
            [['post_code', 'parent_code'], 'string', 'max' => 10],
            [['address'], 'string', 'max' => 255],
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
            'address' => 'Address',
            'description' => 'Description',
            'latitude' => 'Latitude',
            'longitude' => 'Longitude',
            'is_active' => 'Is Active',
            'created_at' => 'Created At',
            'updated_at' => 'Updated At',
            'post_code' => 'Postal Code',
            'parent_code' => 'Center Branch',
            '_key' => 'Key',
        ];
    }

    public static function getLocationList(){
        return \yii\helpers\ArrayHelper::map(self::find()->where(['is_active' => 1])->all(), 'branch_code', 'name');
    }

    /**
     * Gets query for [[CashRegisters]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getCashRegisters()
    {
        return $this->hasMany(CashRegisters::class, ['location_id' => 'id']);
    }

    /**
     * Get status options for dropdown
     * @return array
     */
    public static function optsStatus()
    {
        return [
            self::STATUS_ACTIVE => 'Active',
            self::STATUS_INACTIVE => 'Inactive',
        ];
    }

    /**
     * Get status label
     * @return string
     */
    public function getStatusLabel()
    {
        return self::optsStatus()[$this->is_active];
    }
}
