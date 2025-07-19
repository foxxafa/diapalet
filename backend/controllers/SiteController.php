<?php

namespace app\controllers;

use Yii;
use yii\web\Controller;

class SiteController extends Controller
{
    public function actions()
    {
        return [
            'error' => [
                'class' => 'yii\web\ErrorAction',
            ],
        ];
    }

    public function actionIndex()
    {
        return $this->render('index');
    }

    public function actionHealthCheck()
    {
        Yii::$app->response->format = \yii\web\Response::FORMAT_JSON;
        return [
            'status' => 'ok',
            'timestamp' => date('c'),
            'version' => '1.0.0'
        ];
    }
} 