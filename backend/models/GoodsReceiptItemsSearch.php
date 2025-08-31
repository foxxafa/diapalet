<?php

namespace app\models;

use yii\base\Model;
use yii\data\ActiveDataProvider;
use app\models\GoodsReceiptItems;
use yii\db\Query;

/**
 * GoodsReceiptItemsSearch represents the model behind the search form of `app\models\GoodsReceiptItems`.
 */
class GoodsReceiptItemsSearch extends GoodsReceiptItems
{
    public $StokKodu;
    public $UrunAdi;
    public $warehouse_code;
    public $branch_code;

    /**
     * {@inheritdoc}
     */
    public function rules()
    {
        return [
            [['id', 'receipt_id'], 'integer'],
            [['pallet_barcode', 'expiry_date', 'created_at', 
                'updated_at', 'siparis_key', 'StokKodu', 'warehouse_code', 
                'branch_code', 'UrunAdi'], 'safe'],
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
        $query->joinWith(['urun', 'receipt.warehouse']);

        // add conditions that should always apply here

        $dataProvider = new ActiveDataProvider([
            'query' => $query,
        ]);

        $dataProvider->sort->attributes['StokKodu'] = [
            'asc' => ['goods_receipt_items.StokKodu' => SORT_ASC],
            'desc' => ['goods_receipt_items.StokKodu' => SORT_DESC],
        ];

        $dataProvider->sort->attributes['UrunAdi'] = [
            'asc' => ['urunler.UrunAdi' => SORT_ASC],
            'desc' => ['urunler.UrunAdi' => SORT_DESC],
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

        $query->andFilterWhere(['like', 'pallet_barcode', $this->pallet_barcode])
            ->andFilterWhere(['like', 'siparis_key', $this->siparis_key])
            ->andFilterWhere(['like', 'goods_receipt_items.StokKodu', $this->StokKodu])
            ->andFilterWhere(['like', 'urunler.UrunAdi', $this->UrunAdi]);

        $query->andFilterWhere(['warehouses.warehouse_code' => $this->warehouse_code]);

        if (!empty($this->branch_code)) {
            $query->andFilterWhere(['warehouses.branch_code' => $this->branch_code]);
        }

        // Subquery to find the latest transfer for each goods receipt
        $latestTransferSubquery = (new Query())
            ->select([
                'it.goods_receipt_id',
                's.sales_shelf'
            ])
            ->from(['it' => InventoryTransfers::tableName()])
            ->innerJoin(
                // Sub-subquery to get the max ID for each receipt
                ['it2' => (new Query())
                    ->select([
                        'goods_receipt_id',
                        'max_id' => new \yii\db\Expression('MAX(id)')
                    ])
                    ->from(InventoryTransfers::tableName())
                    ->where(['is not', 'goods_receipt_id', null]) // Exclude nulls to be safe
                    ->groupBy('goods_receipt_id')
                ],
                'it.id = it2.max_id'
            )
            ->leftJoin(['s' => Shelfs::tableName()], 's.code COLLATE utf8mb4_turkish_ci = it.to_shelf COLLATE utf8mb4_turkish_ci');

        // Join the main query with the subquery
        $query->leftJoin(['latest_transfer' => $latestTransferSubquery], 'latest_transfer.goods_receipt_id = goods_receipt_items.receipt_id');

        // Filter out items whose latest transfer was to a sales shelf
        $query->andWhere([
            'or',
            ['latest_transfer.sales_shelf' => null], // This handles items with no transfers
            ['latest_transfer.sales_shelf' => 0]  // This handles items whose last transfer was to a non-sales shelf
        ]);

        return $dataProvider;
    }
}
