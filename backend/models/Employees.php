<?php

namespace app\models;

use Yii;

/**
 * This is the model class for table "employees".
 *
 * @property int $id
 * @property string $first_name
 * @property string $last_name
 * @property string $branch_code
 * @property string $role
 * @property string $username
 * @property string $password
 * @property string $start_date
 * @property string|null $end_date
 * @property int $is_active
 * @property string $created_at
 * @property string $updated_at
 * @property string $warehouse_code
 *
 * @property Locations $location
 */
class Employees extends \yii\db\ActiveRecord implements \yii\web\IdentityInterface
{
    /**
     * {@inheritdoc}
     */
    public static function tableName()
    {
        return 'employees';
    }

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['end_date', 'first_name', 'last_name', 'role', 'username', 'password', 'start_date'], 'default', 'value' => null],
            [['is_active'], 'default', 'value' => 1],
            [[ 'is_active'], 'integer'],
            [['start_date', 'end_date', 'created_at', 'updated_at'], 'safe'],
            [['first_name', 'last_name', 'role'], 'string', 'max' => 100],
            [['username'], 'string', 'max' => 50],
            [['photo'], 'string', 'max' => 150],
            [['warehouse_code', 'branch_code'], 'string', 'max' => 150],
            [['password'], 'string', 'max' => 255],
            [['username'], 'unique'],
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function attributeLabels()
    {
        return [
            'id' => 'ID',
            'first_name' => 'First Name',
            'last_name' => 'Last Name',
            'branch_code' => 'Branch Code',
            'warehouse_code' => 'Warehouse Code',
            'role' => 'Role',
            'username' => 'Username',
            'password' => 'Password',
            'start_date' => 'Start Date',
            'end_date' => 'End Date',
            'is_active' => 'Is Active',
            'created_at' => 'Created At',
            'updated_at' => 'Updated At',
        ];
    }

    /**
     * Gets query for [[Location]].
     *
     * @return \yii\db\ActiveQuery
     */
    public function getBranches()
    {
        return $this->hasOne(Branches::class, ['branch_code' => 'branch_code']);
    }
    public function getWarehouses()
    {
        return $this->hasOne(Warehouses::class, ['warehouse_code' => 'warehouse_code']);
    }

    public function getCashRegisters()
    {
        return $this->hasMany(CashRegister::class, ['id' => 'cash_register_id'])
            ->viaTable('employee_cash_register', ['employee_id' => 'id']);
    }

    public static function getRoles(){
        return [
            'Till' => 'Till',
            'Driver' => 'Driver',
            'Salesman' => 'Salesman',
            'Operation' => 'Operation',
            'Warehouse' => 'Warehouse',
            'Purchase' => 'Purchase',
            'PayPoint' => 'PayPoint',
        ];
    }
    
    /**
     * {@inheritdoc}
     */
    public static function findIdentity($id)
    {
        return static::findOne($id);
    }

    /**
     * {@inheritdoc}
     */
    public static function findIdentityByAccessToken($token, $type = null)
    {
        throw new \yii\base\NotSupportedException('findIdentityByAccessToken is not implemented.');
    }

    /**
     * {@inheritdoc}
     */
    public function getAuthKey()
    {
        // Eğer authKey sütunu yoksa, ekleyebilir veya benzersiz bir değer döndürebilirsiniz
        return md5($this->id.$this->username);
    }

    /**
     * {@inheritdoc}
     */
    public function validateAuthKey($authKey)
    {
        return $this->getAuthKey() === $authKey;
    }

    /**
     * Validates password
     *
     * @param string $password password to validate
     * @return bool if password provided is valid for current user
     */
    public function validatePassword($password)
    {
        return ($this->password === $password && $this->is_active == 1);
    }

    /**
     * Finds user by username
     *
     * @param string $username
     * @return static|null
     */
    public static function findByUsername($username)
    {
        return self::findOne(['username' => $username]);
    }

    /**
     * {@inheritdoc}
     */
    public function getId()
    {
        return $this->id;
    }
}
