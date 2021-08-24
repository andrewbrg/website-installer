#!/bin/bash

title() {
  printf "\033[1;30;42m";
  printf '%*s\n'  "${COLUMNS:-$(tput cols)}" '' || tr ' ' ' ';
  printf '%-*s\n' "${COLUMNS:-$(tput cols)}" "  # $1" || tr ' ' ' ';
  printf '%*s'  "${COLUMNS:-$(tput cols)}" '' || tr ' ' ' ';
  printf "\033[0m";
  printf "\n\n";
}

notify() {
  printf "\n";
  printf "\033[1;46m %s \033[0m" "$1";
  printf "\n";
}

alert() {
  printf "\n";
  printf "\033[31;7m %s \033[0m" "$1";
  printf "\n";
}

breakLine() {
  printf "\n";
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' || tr ' ' -;
  printf "\n\n";
  sleep .5;
}

processUser() {
  title "Processing User ${NEW_USER}";
   
  if id "${NEW_USER}" &>/dev/null; then
    notify "User ${NEW_USER} already exists, skipping..."
  else
    useradd -m -p"${2}" ${NEW_USER};
    usermod -a -G ${NEW_USER} ${NEW_USER};
    
    mkdir -p "/home/${NEW_USER}/public_html";
    chown -R ${NEW_USER}:nginx "/home/${NEW_USER}";
  
    notify "User ${NEW_USER} created...";
  fi
  
  breakLine;
}


processNginx() {
  title "Processing Nginx";
  
  notify "Installing config file...";
  if [ -f ${NGINX_CONF_FILE} ]; then
    while true; do
      read -p "A config file already exits for ${DOMAIN}, overwrite?" yn
        case $yn in
            [Yy]* ) setupNginxConf; break;;
            [Nn]* ) ;;
            * ) echo "Please answer yes or no.";;
        esac
    done
  else
    setupNginxConf;
  fi
  
  notify "Installing certificates...";
  if [ -f "${SSL_CERT_DIR}/selfsigned.key" ] && [ -f "${SSL_CERT_DIR}/selfsigned.crt" ]; then
    while true; do
      read -p "SSL certificates already exist for ${DOMAIN}, overwrite?" yn
        case $yn in
            [Yy]* ) setupNginxCerts; break;;
            [Nn]* ) ;;
            * ) echo "Please answer yes or no.";;
        esac
    done
  else
    setupNginxCerts;
  fi

  breakLine;
}

setupNginxConf() {
  cp "nginx.conf.template" "${NGINX_CONF_FILE}";
  sed -i -e "s/_domain/${DOMAIN}/g" "${NGINX_CONF_FILE}";
  sed -i -e "s/_user/${NEW_USER}/g" "${NGINX_CONF_FILE}";

  touch "/var/log/nginx/${DOMAIN}.access.log";
  touch "/var/log/nginx/${DOMAIN}.error.log";
  chown nginx "/var/log/nginx/${DOMAIN}.access.log";
  chown nginx "/var/log/nginx/${DOMAIN}.error.log";

  local CF_DIR="/etc/nginx/conf.d/inc";
  
  if [ ! -f ${CF_DIR} ]; then
    mkdir -p ${CF_DIR};
    cp "cloudflare.conf" "${CF_DIR}/cloudflare.conf";
  fi
  
  notify "New nginx config created at ${NGINX_CONF_FILE}";
  breakLine;
}

setupNginxCerts() {
  mkdir -p "${SSL_CERT_DIR}";
  openssl req -x509 -nodes -days 9365 -newkey rsa:2048 -keyout "${SSL_CERT_DIR}/selfsigned.key" -out "${SSL_CERT_DIR}/selfsigned.crt";
  chown -R nginx "${SSL_CERT_DIR}";
  
  notify "New certificates installed at ${SSL_CERT_DIR}";
  breakLine;
}

processFpmPool() {
  title "Processing PHP-FPM Pool";
  
  notify "Installing config file...";
  if [ -f "${FPM_POOL_FILE}" ]; then
    while true; do
      read -p "FPM pool already exist for ${DOMAIN}, overwrite?" yn
        case $yn in
            [Yy]* ) setupFpmPool; break;;
            [Nn]* ) ;;
            * ) echo "Please answer yes or no.";;
        esac
    done
  else
    setupFpmPool;
  fi
}

setupFpmPool() {
  cp "php-pool.conf.template" "${FPM_POOL_FILE}";
  sed -i -e "s/_domain/${DOMAIN}/g" "${FPM_POOL_FILE}";
  sed -i -e "s/_user/${NEW_USER}/g" "${FPM_POOL_FILE}";

  touch "/var/log/php-fpm/${DOMAIN}-slow.log";
  touch "/var/log/php-fpm/${DOMAIN}-error.log";
  chown ${NEW_USER} "/var/log/php-fpm/${DOMAIN}-slow.log";
  chown ${NEW_USER} "/var/log/php-fpm/${DOMAIN}-error.log";

  mkdir -p "/var/lib/php/session/${DOMAIN}";
  mkdir -p "/var/lib/php/wsdlcache/${DOMAIN}";
  chown -R ${NEW_USER} "/var/lib/php/session/${DOMAIN}";
  chown -R ${NEW_USER} "/var/lib/php/wsdlcache/${DOMAIN}";

  notify "New PHP-FPM pool created at: ${FPM_POOL_FILE}";
  breakLine;
}

restartServices() {
  title "Restarting Services";
  
  local PHP_SERVICE="php$(php -v | head -n 1 | cut -d " " -f 2 | cut -f1-2 -d".")-fpm";
  
  notify "Restarting PHP-FPM pool...";
  systemctl restart ${PHP_SERVICE};
  if [ "$(service ${PHP_SERVICE} status | grep "(running)")" == '' ]; then
    alert "PHP-FPM crashed - Removing added config file and restarting the service!";
    rm -f "${FPM_POOL_FILE}";
    
    systemctl restart ${PHP_SERVICE};
    systemctl status ${PHP_SERVICE};
  fi
  breakLine;
  
  notify "Reloading nginx to apply configs...";
  systemctl reload nginx;
  if [ "$(systemctl status nginx | grep "(running)")" == '' ]; then
    alert "Nginx crashed - Removing added config and restarting the service!";
    rm -f "${NGINX_CONF_FILE}";
    
    systemctl restart nginx;
    systemctl status nginx;
  fi
  breakLine;
}

## Checks
##############################################
CAN_PROCEED=1;
DOMAIN=$1;
NEW_USER=${DOMAIN//./};

if [ $(which nginx) == '' ]; then
  notify "Ngnix binary missing, please install nginx first...";
  CAN_PROCEED=0;
fi

if [ $(which php) == '' ]; then
  notify "PHP binary missing, please install PHP-FPM first...";
  CAN_PROCEED=0;
fi

if [ ${CAN_PROCEED} -eq 0 ]; then
  exit;
fi

if [ "${EUID}" -ne 0 ]; then 
  notify "Please do run this script as root.";
  exit;
fi

if [ "${1}" == '' ]; then
  notify 'You must pass the full domain including TLD: e.g. ./install.sh mywebsite.com';
  exit;
fi

if [ "${2}" == '' ]; then
  notify "You must pass a password for the new user ${NEW_USER}: e.g. ./install.sh mywebsite.com mypassword";
  exit;
fi

## Installation
##############################################
SSL_CERT_DIR="/etc/nginx/ssl/${DOMAIN}";
NGINX_CONF_FILE="/etc/nginx/conf.d/${DOMAIN}.conf";
FPM_POOL_FILE="/etc/php-fpm.d/${DOMAIN}.conf";

processUser;
processNginx;
processFpmPool;
restartServices;

## Summary
##############################################

notify "Installation summary:";
echo -e "- New user \033[1;4m${NEW_USER}\033[0m available with a home directory at \033[1;4m/home/${NEW_USER}\033[0m.";
echo -e "- Nginx config for \033[1;4m${DOMAIN}\033[0m and www.\033[1;4m${DOMAIN}\033[0m on HTTP/S created at \
\033[1;4m${NGINX_CONF_FILE}\033[0m with SSL certificates located at \033[1;4m${SSL_CERT_DIR}\033[0m.";
echo -e "- PHP-FPM pool running under user \033[1;4m${NEW_USER}\033[0m with config located at \033[1;4m${FPM_POOL_FILE}\033[0m.";

notify "Please ensure the following SeLinux setup has been applied:";
echo 'semanage enforce -a httpd_t;';
echo 'setsebool -P httpd_enable_homedirs 1;';
echo 'setsebool -P httpd_can_network_connect 1;';
echo 'setsebool -P httpd_can_network_connect_db 1;';
breakLine;