#!/bin/bash
# kgpolsm-cloud Mail Server & Roundcube Admin Setup Script
# Compatible with Debian 12/13 (Dovecot 2.4+)

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

DOMAIN="kgpolsm.cloud"
MYSQL_ROOT_PASS="dlwlgh44!!"
DB_USER="mailuser"
DB_PASS="mailpass123"

echo "1. Installing Packages..."
apt update
apt install -y postfix postfix-mysql dovecot-core dovecot-imapd dovecot-pop3d dovecot-mysql mariadb-server

echo "2. Setting up MariaDB..."
mysql -e "CREATE DATABASE IF NOT EXISTS mailserver;"
mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';"
mysql -e "GRANT ALL PRIVILEGES ON mailserver.* TO '${DB_USER}'@'127.0.0.1';"
mysql -e "FLUSH PRIVILEGES;"

mysql mailserver -e "
CREATE TABLE IF NOT EXISTS virtual_domains (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(50) NOT NULL
);
CREATE TABLE IF NOT EXISTS virtual_users (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    domain_id INT NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(150) NOT NULL,
    is_admin TINYINT(1) DEFAULT 0,
    active TINYINT(1) DEFAULT 1,
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS virtual_aliases (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    domain_id INT NOT NULL,
    source VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    FOREIGN KEY (domain_id) REFERENCES virtual_domains(id) ON DELETE CASCADE
);
INSERT IGNORE INTO virtual_domains (name) VALUES ('${DOMAIN}');
"

echo "3. Creating Virtual Mail User (vmail)..."
groupadd -g 5000 vmail
useradd -g vmail -u 5000 vmail -d /var/vmail -m
chown -R vmail:vmail /var/vmail
chmod -R 770 /var/vmail

echo "4. Configuring Postfix..."
cat > /etc/postfix/mysql-virtual-mailbox-domains.cf <<EOF
user = ${DB_USER}
password = ${DB_PASS}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_domains WHERE name='%s'
EOF

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf <<EOF
user = ${DB_USER}
password = ${DB_PASS}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT 1 FROM virtual_users WHERE email='%s' AND active=1
EOF

cat > /etc/postfix/mysql-virtual-alias-maps.cf <<EOF
user = ${DB_USER}
password = ${DB_PASS}
hosts = 127.0.0.1
dbname = mailserver
query = SELECT destination FROM virtual_aliases WHERE source='%s'
EOF

postconf -e "virtual_mailbox_domains = mysql:/etc/postfix/mysql-virtual-mailbox-domains.cf"
postconf -e "virtual_mailbox_maps = mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf"
postconf -e "virtual_alias_maps = mysql:/etc/postfix/mysql-virtual-alias-maps.cf"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
postconf -e "virtual_uid_maps = static:5000"
postconf -e "virtual_gid_maps = static:5000"
postconf -e "virtual_mailbox_base = /var/vmail"

echo "5. Configuring Dovecot 2.4..."
cat > /etc/dovecot/conf.d/auth-sql.conf.ext <<EOF
passdb sql {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
userdb sql {
  driver = sql
  args = /etc/dovecot/dovecot-sql.conf.ext
}
EOF

cat > /etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=127.0.0.1 dbname=mailserver user=${DB_USER} password=${DB_PASS}
default_pass_scheme = SHA512-CRYPT
password_query = SELECT email as user, password FROM virtual_users WHERE email = '%u' AND active=1
user_query = SELECT email as user, 5000 AS uid, 5000 AS gid, concat('/var/vmail/', '%{domain}', '/', '%{username}') AS home FROM virtual_users WHERE email = '%u'
EOF

sed -i 's/^#mail_driver =.*/mail_driver = maildir/' /etc/dovecot/conf.d/10-mail.conf
sed -i "s|^#mail_path =.*|mail_path = /var/vmail/%{user\|domain}/%{user\|username}|" /etc/dovecot/conf.d/10-mail.conf
sed -i 's/disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^dovecot_config_version =.*/dovecot_config_version = 2.4/' /etc/dovecot/dovecot.conf

systemctl restart dovecot
systemctl restart postfix

echo "6. Setting up Roundcube Admin Plugin..."
mkdir -p /var/www/roundcube/plugins/admin_button
cp ./admin.php /var/www/roundcube/admin.php
cp ./admin_button.php /var/www/roundcube/plugins/admin_button/admin_button.php
chown -R www-data:www-data /var/www/roundcube/admin.php /var/www/roundcube/plugins/admin_button

sed -i "/\$config\['plugins'\] = \[/a \    'admin_button'," /var/www/roundcube/config/config.inc.php
sed -i "/\$config\['username_domain'\]/d" /var/www/roundcube/config/config.inc.php
echo "\$config['username_domain'] = '${DOMAIN}';" >> /var/www/roundcube/config/config.inc.php

echo "Setup Complete!"
