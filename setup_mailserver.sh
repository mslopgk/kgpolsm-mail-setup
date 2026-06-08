#!/bin/bash
# ==============================================================================
#  kgpolsm-cloud Mail Server & Webmail & Admin Console Setup Script
#  Target OS: Debian 12/13, Ubuntu 22.04/24.04 (Compatible with Dovecot 2.4+)
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
#  1. Default Configurations (Modify as needed)
# ------------------------------------------------------------------------------
DOMAIN="kgpolsm.cloud"
SUBDOMAIN="mail.kgpolsm.cloud"

# Databases Settings
DB_USER="mailuser"
DB_PASS="mailpass123"      # Change this to a secure password
RC_DB_USER="roundcube"
RC_DB_PASS=$(openssl rand -base64 12 | tr -d '/+=')

# Initial Admin Mail Account Settings
ADMIN_MAIL_ID="kgpolsm"    # Will create kgpolsm@kgpolsm.cloud
ADMIN_PASSWORD="dlwlgh44!!"  # Initial password for email & roundcube admin console

# Software Versions
RC_VERSION="1.6.9"

echo "=========================================================================="
echo " Starting Mail Server Setup for ${DOMAIN} (${SUBDOMAIN})"
echo "=========================================================================="

# Ensure running as root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Please run this script as root (sudo)."
  exit 1
fi

# ------------------------------------------------------------------------------
#  2. Package Installation
# ------------------------------------------------------------------------------
echo ">>> Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt update

# Fix broken packages if any
dpkg --configure -a --force-confdef --force-confold || true

# Install stack packages
apt install -y \
  nginx \
  mariadb-server \
  php-fpm php-mysql php-mbstring php-xml php-curl php-intl php-zip \
  postfix postfix-mysql \
  dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql dovecot-sieve \
  wget unzip openssl composer ufw

# ------------------------------------------------------------------------------
#  3. MariaDB / MySQL Databases Setup
# ------------------------------------------------------------------------------
echo ">>> Setting up MariaDB databases..."
systemctl start mariadb
systemctl enable mariadb

# Create mailserver DB and credentials
mysql -e "CREATE DATABASE IF NOT EXISTS mailserver DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON mailserver.* TO '${DB_USER}'@'localhost';"

# Create roundcube DB and credentials
mysql -e "CREATE DATABASE IF NOT EXISTS roundcube DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"
mysql -e "CREATE USER IF NOT EXISTS '${RC_DB_USER}'@'localhost' IDENTIFIED BY '${RC_DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON roundcube.* TO '${RC_DB_USER}'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

# Generate passwords
# Generate admin password hash (bcrypt for PHP Admin Console)
ADMIN_HASH=$(php -r "echo password_hash('${ADMIN_PASSWORD}', PASSWORD_DEFAULT);")
# Generate user password hash (SHA512-CRYPT for Dovecot)
MAIL_HASH=$(doveadm pw -s SHA512-CRYPT -p "${ADMIN_PASSWORD}")

# Import schemas for Mailserver
echo ">>> Creating mailserver database schema..."
mysql mailserver <<EOF
CREATE TABLE IF NOT EXISTS virtual_domains (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS virtual_users (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    domain_id INT NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(150) NOT NULL,
    quota INT DEFAULT 0,
    active TINYINT(1) DEFAULT 1,
    smtp_enabled TINYINT(1) DEFAULT 1,
    pop3_enabled TINYINT(1) DEFAULT 1,
    imap_enabled TINYINT(1) DEFAULT 1,
    is_admin TINYINT(1) DEFAULT 0,
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS virtual_aliases (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    domain_id INT NOT NULL,
    source VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS admin_users (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    password VARCHAR(150) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO virtual_domains (id, name) VALUES (1, '${DOMAIN}');
-- Create the initial admin dashboard login
INSERT IGNORE INTO admin_users (username, password) VALUES ('${ADMIN_MAIL_ID}', '${ADMIN_HASH}');
-- Create the initial email account and mark as admin
INSERT IGNORE INTO virtual_users (domain_id, email, password, is_admin) VALUES (1, '${ADMIN_MAIL_ID}@${DOMAIN}', '${MAIL_HASH}', 1);
EOF

# ------------------------------------------------------------------------------
#  4. Create Virtual Mail User (vmail)
# ------------------------------------------------------------------------------
echo ">>> Creating Virtual Mail User (vmail)..."
groupadd -g 5000 vmail || true
useradd -g vmail -u 5000 vmail -d /var/vmail -m || true
chown -R vmail:vmail /var/vmail
chmod -R 770 /var/vmail

# ------------------------------------------------------------------------------
#  5. Postfix Configuration
# ------------------------------------------------------------------------------
echo ">>> Configuring Postfix..."

cat <<EOF > /etc/postfix/mysql-virtual-mailbox-domains.cf
user = ${DB_USER}
password = ${DB_PASS}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF

cat <<EOF > /etc/postfix/mysql-virtual-mailbox-maps.cf
user = ${DB_USER}
password = ${DB_PASS}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT CONCAT(SUBSTRING_INDEX(email,'@',-1), '/', SUBSTRING_INDEX(email,'@',1), '/Maildir/') FROM virtual_users WHERE email='%s' AND active=1
EOF

cat <<EOF > /etc/postfix/mysql-virtual-alias-maps.cf
user = ${DB_USER}
password = ${DB_PASS}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF

# Update Postfix parameters
postconf -e "myhostname = ${SUBDOMAIN}"
postconf -e "myorigin = ${DOMAIN}"
postconf -e "mydestination = localhost.\$mydomain, localhost"
postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf"
postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf"
postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-alias-maps.cf"
postconf -e "virtual_mailbox_base = /var/vmail"
postconf -e "virtual_uid_maps = static:5000"
postconf -e "virtual_gid_maps = static:5000"

# SASL Authentication via Dovecot
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

# SSL/TLS config setup (We'll generate a self-signed cert by default. Replace with Let's Encrypt paths if available)
mkdir -p /etc/nginx/ssl
SSL_CERT="/etc/nginx/ssl/webmail.crt"
SSL_KEY="/etc/nginx/ssl/webmail.key"
if [ ! -f "${SSL_CERT}" ]; then
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "${SSL_KEY}" -out "${SSL_CERT}" -subj "/C=KR/ST=Seoul/L=Seoul/O=Mail/CN=${SUBDOMAIN}"
fi

postconf -e "smtpd_tls_cert_file = ${SSL_CERT}"
postconf -e "smtpd_tls_key_file = ${SSL_KEY}"
postconf -e "smtpd_tls_security_level = may"
postconf -e "smtp_tls_security_level = may"

# ------------------------------------------------------------------------------
#  6. Dovecot 2.4+ Configuration
# ------------------------------------------------------------------------------
echo ">>> Configuring Dovecot 2.4+..."

# Backup existing configs
[ -f /etc/dovecot/conf.d/10-auth.conf ] && cp /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.bak || true
[ -f /etc/dovecot/conf.d/10-mail.conf ] && cp /etc/dovecot/conf.d/10-mail.conf /etc/dovecot/conf.d/10-mail.conf.bak || true

# Config Dovecot variables
sed -i 's/#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf || true
sed -i 's/disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf || true
sed -i 's/auth_mechanisms = plain/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf || true

# Enable auth-sql.conf.ext and disable auth-system.conf.ext
sed -i 's/!include auth-system.conf.ext/#!include auth-system.conf.ext/' /etc/dovecot/conf.d/10-auth.conf || true
sed -i 's/#!include auth-sql.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf || true

# Mail location
cat <<EOF > /etc/dovecot/conf.d/10-mail.conf
mail_driver = maildir
mail_path = /var/vmail/%{user|domain}/%{user|username}/Maildir
mail_privileged_group = mail
namespace inbox {
  inbox = yes
  mailbox Drafts {
    special_use = \\Drafts
  }
  mailbox Junk {
    special_use = \\Junk
  }
  mailbox Trash {
    special_use = \\Trash
  }
  mailbox Sent {
    special_use = \\Sent
  }
  mailbox "Sent Messages" {
    special_use = \\Sent
  }
}
EOF

# Dovecot Master Listener
cat <<EOF > /etc/dovecot/conf.d/10-master.conf
service imap-login {
  inet_listener imap {
    port = 143
  }
}
service pop3-login {
  inet_listener pop3 {
    port = 110
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF

# SSL setting for Dovecot
sed -i "s|ssl_cert =.*|ssl_cert = <${SSL_CERT}|" /etc/dovecot/conf.d/10-ssl.conf || true
sed -i "s|ssl_key =.*|ssl_key = <${SSL_KEY}|" /etc/dovecot/conf.d/10-ssl.conf || true

# Write Dovecot 2.4 SQL mapping config
cat <<EOF > /etc/dovecot/conf.d/auth-sql.conf.ext
sql_driver = mysql
mysql 127.0.0.1 {
  dbname = mailserver
  user = ${DB_USER}
  password = ${DB_PASS}
}

passdb sql {
  query = SELECT email AS user, password FROM virtual_users WHERE email = '%{user}' AND active = 1
  default_password_scheme = SHA512-CRYPT
}

userdb sql {
  query = SELECT email AS user, 5000 AS uid, 5000 AS gid, concat('/var/vmail/', '%{user|domain}', '/', '%{user|username}') AS home FROM virtual_users WHERE email = '%{user}' AND active = 1
}
EOF

# Set configuration version to 2.4 in dovecot.conf
sed -i 's/^dovecot_config_version =.*/dovecot_config_version = 2.4/' /etc/dovecot/dovecot.conf || true

# ------------------------------------------------------------------------------
#  7. Roundcube Setup
# ------------------------------------------------------------------------------
echo ">>> Installing and configuring Roundcube Webmail..."
cd /var/www
if [ ! -d "/var/www/roundcube" ]; then
    echo "Downloading Roundcube v${RC_VERSION}..."
    wget -q "https://github.com/roundcube/roundcubemail/releases/download/${RC_VERSION}/roundcubemail-${RC_VERSION}-complete.tar.gz"
    tar -xzf "roundcubemail-${RC_VERSION}-complete.tar.gz"
    mv "roundcubemail-${RC_VERSION}" roundcube
    rm "roundcubemail-${RC_VERSION}-complete.tar.gz"
    
    chown -R www-data:www-data /var/www/roundcube
    chmod -R 755 /var/www/roundcube

    # Import initial SQL to Roundcube database
    mysql roundcube < /var/www/roundcube/SQL/mysql.initial.sql
fi

RC_CONF="/var/www/roundcube/config/config.inc.php"
cp /var/www/roundcube/config/config.inc.php.sample $RC_CONF

# Modify Roundcube config parameters
sed -i "s|^\$config\['db_dsnw'\].*|\$config['db_dsnw'] = 'mysql://${RC_DB_USER}:${RC_DB_PASS}@localhost/roundcube';|" $RC_CONF
sed -i "s|^\$config\['default_host'\].*|\$config['default_host'] = 'localhost';|" $RC_CONF
sed -i "s|^\$config\['smtp_server'\].*|\$config['smtp_server'] = 'localhost';|" $RC_CONF
sed -i "s|^\$config\['smtp_port'\].*|\$config['smtp_port'] = 25;|" $RC_CONF
sed -i "s|^\$config\['smtp_user'\].*|\$config['smtp_user'] = '%u';|" $RC_CONF
sed -i "s|^\$config\['smtp_pass'\].*|\$config['smtp_pass'] = '%p';|" $RC_CONF
sed -i "s|^\$config\['des_key'\].*|\$config['des_key'] = '$(openssl rand -base64 24 | tr -d '\n')';|" $RC_CONF

# Append default domain configs so users don't need to type full email addresses
grep -q "mail_domain" $RC_CONF || echo "\$config['mail_domain'] = '${DOMAIN}';" >> $RC_CONF
sed -i "s|^\$config\['mail_domain'\].*|\$config['mail_domain'] = '${DOMAIN}';|" $RC_CONF
grep -q "username_domain" $RC_CONF || echo "\$config['username_domain'] = '${DOMAIN}';" >> $RC_CONF
sed -i "s|^\$config\['username_domain'\].*|\$config['username_domain'] = '${DOMAIN}';|" $RC_CONF

# ------------------------------------------------------------------------------
#  8. Roundcube Admin Plugin Setup
# ------------------------------------------------------------------------------
echo ">>> Setting up Roundcube Admin Console & Plugin..."

# Copy files from repository directory (script assumed to run in repo root directory)
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

mkdir -p /var/www/roundcube/plugins/admin_button
cp "${SCRIPT_DIR}/admin.php" /var/www/roundcube/admin.php
cp "${SCRIPT_DIR}/admin_button.php" /var/www/roundcube/plugins/admin_button/admin_button.php

# Dynamically replace DB configuration in php files
sed -i "s/dbname=mailserver;charset=utf8mb4\", \"mailuser\", \"mailpass123\"/dbname=mailserver;charset=utf8mb4\", \"${DB_USER}\", \"${DB_PASS}\"/g" /var/www/roundcube/admin.php
sed -i "s/dbname=mailserver;charset=utf8mb4\", \"mailuser\", \"mailpass123\"/dbname=mailserver;charset=utf8mb4\", \"${DB_USER}\", \"${DB_PASS}\"/g" /var/www/roundcube/plugins/admin_button/admin_button.php

# Enable admin_button plugin in config.inc.php
sed -i "/\$config\['plugins'\] = \[/a \    'admin_button'," $RC_CONF

chown -R www-data:www-data /var/www/roundcube/admin.php /var/www/roundcube/plugins/admin_button

# ------------------------------------------------------------------------------
#  9. Nginx & PHP-FPM Configuration
# ------------------------------------------------------------------------------
echo ">>> Configuring Nginx..."

# Dynamically detect PHP-FPM socket path
PHP_SOCK=$(find /run/php/ -name "php*-fpm.sock" | head -n 1)
if [ -z "${PHP_SOCK}" ]; then
  # Fallback guess
  PHP_SOCK="/run/php/php8.4-fpm.sock"
fi

cat <<EOF > /etc/nginx/sites-available/roundcube
server {
    listen 80;
    listen [::]:80;
    server_name ${SUBDOMAIN} ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${SUBDOMAIN} ${DOMAIN};

    root /var/www/roundcube;
    index index.php index.html index.htm;

    ssl_certificate ${SSL_CERT};
    ssl_certificate_key ${SSL_KEY};

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_SOCK};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ ^/(README|INSTALL|LICENSE|CHANGELOG|UPGRADING)$ {
        deny all;
    }
    location ~ ^/(bin|SQL)/ {
        deny all;
    }
}
EOF

ln -sf /etc/nginx/sites-available/roundcube /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default || true

# ------------------------------------------------------------------------------
#  10. UFW Firewall Setup
# ------------------------------------------------------------------------------
echo ">>> Configuring UFW Firewall..."
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 25/tcp
ufw allow 587/tcp
ufw allow 465/tcp
ufw allow 143/tcp
ufw allow 993/tcp
ufw allow 110/tcp
ufw allow 995/tcp
ufw --force enable

# ------------------------------------------------------------------------------
#  11. Restart Services & Final Verification
# ------------------------------------------------------------------------------
echo ">>> Restarting services..."
systemctl restart mariadb dovecot postfix nginx

PHP_SERVICE=$(systemctl list-units --type=service --state=running | grep php | awk '{print $1}' | head -n 1)
if [ ! -z "${PHP_SERVICE}" ]; then
  systemctl restart "${PHP_SERVICE}"
fi

echo "=========================================================================="
echo " Setup Completed Successfully!"
echo "=========================================================================="
echo " - Mail Domain: ${DOMAIN}"
echo " - Webmail URL: https://${SUBDOMAIN} (or https://<server-ip>)"
echo " - Admin User:  ${ADMIN_MAIL_ID}@${DOMAIN}"
echo " - Password:    ${ADMIN_PASSWORD}"
echo " - DB Settings: Database 'mailserver' configured."
echo " - Roundcube DB Password: ${RC_DB_PASS}"
echo "=========================================================================="
echo " Note: We created a self-signed SSL certificate."
echo " To enable Let's Encrypt Certbot, run:"
echo "   sudo apt install certbot python3-certbot-nginx -y"
echo "   sudo certbot --nginx -d ${SUBDOMAIN}"
echo "=========================================================================="
