<?php

namespace app\models;

use yii\base\Model;
use yii\data\ActiveDataProvider;
use app\models\GoodsReceiptItems;

/**
 * GoodsReceiptItemsSearch represents the model behind the search form of `app\models\GoodsReceiptItems`.
 */
class GoodsReceiptItemsSearch extends GoodsReceiptItems
{
    public $StokKodu;

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['id', 'receipt_id'], 'integer'],
            [['urun_key', 'pallet_barcode', 'expiry_date', 'created_at', 'updated_at', 'siparis_key', 'StokKodu'], 'safe'],
            [['quantity_received'], 'number'],
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
        $query = GoodsReceiptItems::find();
        $query->joinWith(['urunKey']);

        // add conditions that should always apply here

        $dataProvider = new ActiveDataProvider([
            'query' => $query,
        ]);

        $dataProvider->sort->attributes['StokKodu'] = [
            'asc' => ['urunler.StokKodu' => SORT_ASC],
            'desc' => ['urunler.StokKodu' => SORT_DESC],
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
            'receipt_id' => $this->receipt_id,
            'quantity_received' => $this->quantity_received,
            'expiry_date' => $this->expiry_date,
            'created_at' => $this->created_at,
            'updated_at' => $this->updated_at,
        ]);

        $query->andFilterWhere(['like', 'urun_key', $this->urun_key])
            ->andFilterWhere(['like', 'pallet_barcode', $this->pallet_barcode])
            ->andFilterWhere(['like', 'siparis_key', $this->siparis_key])
            ->andFilterWhere(['like', 'urunler.StokKodu', $this->StokKodu]);

        return $dataProvider;
    }
}
