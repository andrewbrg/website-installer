#!/bin/bash

VERSION_PHP="7.4";

cd ${HOME};
apt full-upgrade;

apt install -y \
    selinux-basics \
    selinux-policy-default \
    lsb-release \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    wget \
    htop \
    nano \
    vim;

curl -fsSL "https://packages.sury.org/php/apt.gpg" | sudo apt-key add -;
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee "/etc/apt/sources.list.d/php.list";

wget "https://dev.mysql.com/get/mysql-apt-config_0.8.18-1_all.deb";
apt install -f ./mysql-apt-config_0.8.18-1_all.deb;
rm -f mysql-apt-config_0.8.18-1_all.deb;

apt update;
apt install -y php7.4-{bcmath,cli,curl,common,gd,ds,igbinary,dom,fpm,gettext,intl,mbstring,mysql,zip};
apt install -y php8.0-{bcmath,cli,curl,common,gd,ds,igbinary,dom,fpm,gettext,intl,mbstring,mysql,zip};

sudo update-alternatives --set php "/usr/bin/php${VERSION_PHP}";
sudo update-alternatives --set phar "/usr/bin/phar${VERSION_PHP}";
sudo update-alternatives --set phar.phar "/usr/bin/phar.phar${VERSION_PHP}";
sudo update-alternatives --set phpize "/usr/bin/phpize${VERSION_PHP}";
sudo update-alternatives --set php-config "/usr/bin/php-config${VERSION_PHP}";

service php8.0-fpm stop;
systemctl enable php${VERSION_PHP}-fpm;
systemctl disable php8.0-fpm;

apt install -y git nginx;

systemctl enable nginx;
systemctl start nginx;

php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php -r "if (hash_file('sha384', 'composer-setup.php') === '756890a4488ce9024fc62c56153228907f1545c228516cbf63f885e036d37e9a59d27d63f46af1d4d07ee0f76181c7d3') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
php composer-setup.php
php -r "unlink('composer-setup.php');"
sudo mv composer.phar /usr/local/bin/composer;

apt install -y mysql-server;

cd "/usr/share";
composer create-project phpmyadmin/phpmyadmin;
chown -R www-data:www-data "/usr/share/phpmyadmin";
cp "configs/phpmyadmin.conf" "/etc/nginx/conf.d";
systemctl reload nginx;

mkdir -p "/etc/nginx/ssl/db.webagency";
openssl req -x509 -nodes -days 9365 -newkey rsa:2048 -keyout "/etc/nginx/ssl/db.webagency/selfsigned.key" -out "/etc/nginx/ssl/db.webagency/selfsigned.crt";
chown -R www-data "/etc/nginx/ssl/db.webagency";

mkdir "${HOME}/installer";
cd "${HOME}/installer";
git clone "https://github.com/andrewbrg/website-installer.git" .;
chmod +x install.sh

apt autoremove --purge;

semanage permissive -a httpd_t;
setsebool -P httpd_enable_homedirs 1;
setsebool -P httpd_can_network_connect 1;
setsebool -P httpd_can_network_connect_db 1;
