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

# Install dependencies for production, without dev packages
RUN composer install --no-dev --optimize-autoloader

# Copy the rest of the backend application code
COPY backend/ .

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