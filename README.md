# kgpolsm-cloud Mail Server & Admin Panel Setup

This repository contains the scripts and files needed to deploy a fully functional Virtual Mailbox server (Postfix + Dovecot 2.4 + MariaDB) with a custom, minimalistic Admin Panel integrated directly into Roundcube.

## Features
- **Virtual Mailbox**: Manage users without creating system accounts.
- **Dovecot 2.4 Ready**: Uses updated syntax (`mail_driver`, inline SQL config).
- **Roundcube Admin Plugin**: Users with `is_admin = 1` in the database get an "Admin Panel" button inside Roundcube to add/suspend/delete accounts.
- **Domain Auto-Append**: Users can log in using just their ID instead of full email.

## How to Deploy on a New Server

1. **Clone this repository** to your new server.
2. Ensure you have Roundcube installed at `/var/www/roundcube`.
3. Give execution permission to the setup script:
   ```bash
   chmod +x setup_mailserver.sh
   ```
4. Run the script as root:
   ```bash
   sudo ./setup_mailserver.sh
   ```
5. Log into MariaDB and insert your initial Admin account:
   ```sql
   USE mailserver;
   -- Generates a SHA512-CRYPT password. You can use PHP's crypt() or Python's crypt module.
   INSERT INTO virtual_users (domain_id, email, password, is_admin, active) VALUES (1, 'admin@kgpolsm.cloud', '{SHA512-CRYPT}$6$salt$hashed...', 1, 1);
   ```

## Files
- `setup_mailserver.sh`: Master installation bash script.
- `admin.php`: The clean, minimalistic PHP Admin dashboard.
- `admin_button.php`: The Roundcube plugin that detects admin users and injects the dashboard button.
