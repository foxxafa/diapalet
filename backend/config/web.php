<?php
return [
    'id' => 'diapalet-backend',
    'basePath' => dirname(__DIR__),
    'bootstrap' => ['log'],
    'aliases' => [
        '@bower' => '@vendor/bower-asset',
        '@npm'   => '@vendor/npm-asset',
    ],
    'components' => [
        'request' => [
            'cookieValidationKey' => getenv('COOKIE_VALIDATION_KEY') ?: 'default-key-change-this',
            'parsers' => [
                'application/json' => 'yii\web\JsonParser',
            ]
        ],
        'cache' => [
            'class' => 'yii\caching\FileCache',
        ],
        'user' => [
            'identityClass' => 'app\models\User',
            'enableAutoLogin' => true,
        ],
        'errorHandler' => [
            'errorAction' => 'site/error',
        ],
        'mailer' => [
            'class' => 'yii\swiftmailer\Mailer',
            'useFileTransport' => true,
        ],
        'log' => [
            'traceLevel' => YII_DEBUG ? 3 : 0,
            'targets' => [
                [
                    'class' => 'yii\log\FileTarget',
                    'levels' => ['error', 'warning'],
                ],
            ],
        ],
        'db' => [
            'class' => 'yii\db\Connection',
            'dsn' => 'mysql:host=' . (getenv('DB_HOST') ?: 'localhost') . ';port=' . (getenv('DB_PORT') ?: '3306') . ';dbname=' . (getenv('DB_NAME') ?: 'railway'),
            'username' => getenv('DB_USER') ?: 'root',
            'password' => getenv('DB_PASSWORD') ?: '',
            'charset' => 'utf8mb4',
            'enableSchemaCache' => !YII_DEBUG,
            'schemaCacheDuration' => 3600,
        ],
        'urlManager' => [
            'enablePrettyUrl' => true,
            'showScriptName' => false,
            'rules' => [
                'health-check' => 'terminal/health-check',
                'api/terminal/<action>' => 'terminal/<action>',
                'api/<controller>/<action>' => '<controller>/<action>',
                '<controller>/<action>' => '<controller>/<action>',
            ],
        ],
    ],
    'params' => [
        'dia' => [
            'api_url' => getenv('DIA_API_URL') ?: 'https://aytacfoods.ws.dia.com.tr/api/v3/sis/json',
            'username' => getenv('DIA_USERNAME') ?: 'Ws-03',
            'password' => getenv('DIA_PASSWORD') ?: 'Ws123456.',
            'api_key' => getenv('DIA_API_KEY') ?: 'dbbd8cb8-846f-4379-8d77-505e845db4a2',
        ],
    ],
]; 