<?php

namespace app\models;

use yii\base\Model;
use yii\data\ActiveDataProvider;
use app\models\Employees;

/**
 * EmployeesSearch represents the model behind the search form of `app\models\Employees`.
 */
class EmployeesSearch extends Employees
{
    public $branch_name;
    public $warehouse_name;
    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['id', 'is_active'], 'integer'],
            [['first_name', 'last_name', 'role', 'username', 'password', 'start_date', 'end_date', 'created_at', 'updated_at', 'branch_name', 'warehouse_name', 'branch_code', 'warehouse_code'], 'safe'],
        ];
    }

    /**
     * {@inheritdoc}
     */
    public function scenarios()
    {
        // bypass scenarios() implementation in the parent class
        return Model::scenarios();
    }

    /**
     * Creates data provider instance with search query applied
     *
     * @param array $params
     * @param string|null $formName Form name to be used into `->load()` method.
     *
     * @return ActiveDataProvider
     */
    public function search($params, $formName = null)
    {
        $query = Employees::find();
        $query->joinWith(['branches', 'warehouses']);

        // add conditions that should always apply here

        $dataProvider = new ActiveDataProvider([
            'query' => $query,
        ]);

        $dataProvider->sort->attributes['branch_name'] = [
            'asc' => ['branches.name' => SORT_ASC],
            'desc' => ['branches.name' => SORT_DESC],
        ];

        $dataProvider->sort->attributes['warehouse_name'] = [
            'asc' => ['warehouses.name' => SORT_ASC],
            'desc' => ['warehouses.name' => SORT_DESC],
        ];

        $this->load($params, $formName);

        if (!$this->validate()) {
            // uncomment the following line if you do not want to return any records when validation fails
            // $query->where('0=1');
            return $dataProvider;
        }

        // grid filtering conditions
        $query->andFilterWhere([
            'id' => $this->id,
            'start_date' => $this->start_date,
            'end_date' => $this->end_date,
            'is_active' => $this->is_active,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
            'employees.branch_code' => $this->branch_code,
            'employees.warehouse_code' => $this->warehouse_code,
        ]);

        $query->andFilterWhere(['like', 'first_name', $this->first_name])
            ->andFilterWhere(['like', 'last_name', $this->last_name])
            ->andFilterWhere(['like', 'role', $this->role])
            ->andFilterWhere(['like', 'username', $this->username])
            ->andFilterWhere(['like', 'password', $this->password])
            ->andFilterWhere(['like', 'branches.name', $this->branch_name])
            ->andFilterWhere(['like', 'warehouses.name', $this->warehouse_name]);

        return $dataProvider;
    }
}
