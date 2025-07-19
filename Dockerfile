# PHP 8.1 with Apache base image
FROM php:8.1-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    zip \
    unzip \
    wget \
    && docker-php-ext-install pdo_mysql mbstring exif pcntl bcmath gd zip

# Enable Apache modules
RUN a2enmod rewrite headers

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Set working directory
WORKDIR /var/www/html

# Copy composer files first for better caching
COPY backend/composer.* ./

# Install PHP dependencies (if composer.json exists)
RUN if [ -f composer.json ]; then composer install --no-dev --optimize-autoloader; fi

# Copy the entire backend directory
COPY backend/ ./

# Copy additional backend files if they exist separately
COPY backend/*.php ./
COPY backend/*.sql ./

# Create necessary directories
RUN mkdir -p runtime assets web/assets \
    && chown -R www-data:www-data runtime assets web/assets \
    && chmod -R 775 runtime assets web/assets

# Configure Apache
RUN echo "<VirtualHost *:80>\n\
    DocumentRoot /var/www/html/web\n\
    <Directory /var/www/html/web>\n\
        AllowOverride All\n\
        Require all granted\n\
        DirectoryIndex index.php\n\
    </Directory>\n\
    ErrorLog \${APACHE_LOG_DIR}/error.log\n\
    CustomLog \${APACHE_LOG_DIR}/access.log combined\n\
</VirtualHost>" > /etc/apache2/sites-available/000-default.conf

# Create web directory and index.php if they don't exist
RUN mkdir -p web && \
    if [ ! -f web/index.php ]; then \
        echo "<?php\n\
defined('YII_DEBUG') or define('YII_DEBUG', getenv('YII_DEBUG') ?: false);\n\
defined('YII_ENV') or define('YII_ENV', getenv('YII_ENV') ?: 'prod');\n\
\n\
require __DIR__ . '/../vendor/autoload.php';\n\
require __DIR__ . '/../vendor/yiisoft/yii2/Yii.php';\n\
\n\
\$config = require __DIR__ . '/../config/web.php';\n\
\n\
(new yii\\web\\Application(\$config))->run();" > web/index.php; \
    fi

# Create basic Yii2 structure if it doesn't exist
RUN mkdir -p config controllers models views && \
    if [ ! -f config/web.php ]; then \
        echo "<?php\n\
return [\n\
    'id' => 'basic-app',\n\
    'basePath' => dirname(__DIR__),\n\
    'bootstrap' => ['log'],\n\
    'aliases' => [\n\
        '@bower' => '@vendor/bower-asset',\n\
        '@npm'   => '@vendor/npm-asset',\n\
    ],\n\
    'components' => [\n\
        'request' => [\n\
            'cookieValidationKey' => getenv('COOKIE_VALIDATION_KEY') ?: 'your-secret-key',\n\
            'parsers' => [\n\
                'application/json' => 'yii\\web\\JsonParser',\n\
            ]\n\
        ],\n\
        'cache' => [\n\
            'class' => 'yii\\caching\\FileCache',\n\
        ],\n\
        'user' => [\n\
            'identityClass' => 'app\\models\\User',\n\
            'enableAutoLogin' => true,\n\
        ],\n\
        'errorHandler' => [\n\
            'errorAction' => 'site/error',\n\
        ],\n\
        'mailer' => [\n\
            'class' => 'yii\\swiftmailer\\Mailer',\n\
            'useFileTransport' => true,\n\
        ],\n\
        'log' => [\n\
            'traceLevel' => YII_DEBUG ? 3 : 0,\n\
            'targets' => [\n\
                [\n\
                    'class' => 'yii\\log\\FileTarget',\n\
                    'levels' => ['error', 'warning'],\n\
                ],\n\
            ],\n\
        ],\n\
        'db' => [\n\
            'class' => 'yii\\db\\Connection',\n\
            'dsn' => 'mysql:host=' . getenv('DB_HOST') . ';dbname=' . getenv('DB_NAME'),\n\
            'username' => getenv('DB_USER'),\n\
            'password' => getenv('DB_PASSWORD'),\n\
            'charset' => 'utf8',\n\
        ],\n\
        'urlManager' => [\n\
            'enablePrettyUrl' => true,\n\
            'showScriptName' => false,\n\
            'rules' => [\n\
                'api/<controller>/<action>' => '<controller>/<action>',\n\
            ],\n\
        ],\n\
    ],\n\
    'params' => [],\n\
];" > config/web.php; \
    fi

# Create .htaccess for web directory
RUN echo "RewriteEngine on\n\
# If a directory or a file exists, use it directly\n\
RewriteCond %{REQUEST_FILENAME} !-f\n\
RewriteCond %{REQUEST_FILENAME} !-d\n\
# Otherwise forward it to index.php\n\
RewriteRule . index.php" > web/.htaccess

# Set proper permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Expose port 80
EXPOSE 80

# Create startup script
RUN echo '#!/bin/bash\n\
# Set PORT if not provided\n\
export PORT=${PORT:-80}\n\
# Update Apache configuration with correct port\n\
sed -i "s/:80/:$PORT/g" /etc/apache2/sites-available/000-default.conf\n\
sed -i "s/Listen 80/Listen $PORT/g" /etc/apache2/ports.conf\n\
# Start Apache\n\
exec apache2ctl -D FOREGROUND' > /start.sh && chmod +x /start.sh

# Start Apache
CMD ["/start.sh"] 