import paramiko
import sys

host = '192.168.219.47'
user = 'seongho'
password = 'dlwlgh44!!'

commands = [
    "echo 'dlwlgh44!!' | sudo -S apt-get update",
    "echo 'dlwlgh44!!' | sudo -S apt-get install -y ufw",
    "echo 'dlwlgh44!!' | sudo -S ufw allow 22/tcp",   # SSH
    "echo 'dlwlgh44!!' | sudo -S ufw allow 80/tcp",   # HTTP (Webmail)
    "echo 'dlwlgh44!!' | sudo -S ufw allow 443/tcp",  # HTTPS (Webmail)
    "echo 'dlwlgh44!!' | sudo -S ufw allow 25/tcp",   # SMTP
    "echo 'dlwlgh44!!' | sudo -S ufw allow 587/tcp",  # SMTP Submission
    "echo 'dlwlgh44!!' | sudo -S ufw allow 465/tcp",  # SMTPS
    "echo 'dlwlgh44!!' | sudo -S ufw allow 143/tcp",  # IMAP
    "echo 'dlwlgh44!!' | sudo -S ufw allow 993/tcp",  # IMAPS
    "echo 'dlwlgh44!!' | sudo -S ufw allow 110/tcp",  # POP3
    "echo 'dlwlgh44!!' | sudo -S ufw allow 995/tcp",  # POP3S
    "echo 'dlwlgh44!!' | sudo -S ufw --force enable",
    "echo 'dlwlgh44!!' | sudo -S ufw status verbose"
]

ssh = paramiko.SSHClient()
ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
ssh.connect(host, username=user, password=password)

for cmd in commands:
    print(f"Running: {cmd.split('sudo -S ')[-1]}")
    stdin, stdout, stderr = ssh.exec_command(cmd)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    
    # Ignore typical sudo prompt in stderr
    if err:
        err_lines = [line for line in err.split('\n') if "[sudo] password for" not in line]
        if err_lines:
            print("ERR:", '\n'.join(err_lines))
    if out:
        print("OUT:", out)
    print("-" * 40)

ssh.close()
