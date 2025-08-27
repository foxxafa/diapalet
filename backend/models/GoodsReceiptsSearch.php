<?php

namespace app\models;

use yii\base\Model;
use yii\data\ActiveDataProvider;
use app\models\GoodsReceipts;

/**
 * GoodsReceiptsSearch represents the model behind the search form of `app\models\GoodsReceipts`.
 */
class GoodsReceiptsSearch extends GoodsReceipts
{
    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['goods_receipt_id', 'warehouse_id', 'siparis_id', 'employee_id'], 'integer'],
            [['invoice_number', 'delivery_note_number', 'receipt_date', 'created_at', 'updated_at'], 'safe'],
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
        $query = GoodsReceipts::find();

        // add conditions that should always apply here

        $dataProvider = new ActiveDataProvider([
            'query' => $query,
        ]);

        $this->load($params, $formName);

        if (!$this->validate()) {
            // uncomment the following line if you do not want to return any records when validation fails
            // $query->where('0=1');
            return $dataProvider;
        }

        // grid filtering conditions
        $query->andFilterWhere([
            'goods_receipt_id' => $this->goods_receipt_id,
            'warehouse_id' => $this->warehouse_id,
            'siparis_id' => $this->siparis_id,
            'employee_id' => $this->employee_id,
            'receipt_date' => $this->receipt_date,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
        ]);

        $query->andFilterWhere(['like', 'invoice_number', $this->invoice_number])
            ->andFilterWhere(['like', 'delivery_note_number', $this->delivery_note_number]);

        return $dataProvider;
    }
}
