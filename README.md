# kgpolsm-cloud Mail Server & Webmail & Admin Console Setup

이 저장소는 **Postfix + Dovecot 2.4+ (MySQL/MariaDB 백엔드) 가상 메일박스 서버**와 **Roundcube 웹메일**, 그리고 Roundcube에 완벽히 연동되는 **초소형 관리자 패널(Admin Console)**을 신규 서버나 기존 서버에 한 번에 구축 및 초기화할 수 있게 도와주는 마스터 쉘 스크립트 패키지입니다.

---

## 🚀 주요 기능
- **가상 메일박스(Virtual Mailbox)**: 리눅스 시스템 계정을 생성할 필요 없이 데이터베이스(MariaDB)를 기반으로 다수의 가상 도메인 및 메일 계정 관리.
- **Dovecot 2.4 호환**: 최신 Debian 12/13 등에서 사용되는 Dovecot 2.4+의 새로운 문법(인라인 `mysql` 연결 정보 정의 및 맵 변경)을 완전 지원.
- **PHP-FPM 자동 감지**: 시스템에 설치된 PHP-FPM 버전을 자동으로 스캔하여 Nginx 설정에 동적 연동.
- **Roundcube Admin Plugin**: `virtual_users` 테이블 상 `is_admin = 1` 권한이 있는 관리자 계정으로 로그인 시, Roundcube 화면에 **Admin Panel** 바로가기 링크를 주입하여 간편하게 사용자 등록, 계정 활성/비활성화, 관리자 지정, 삭제 기능을 웹 인터페이스로 처리 가능.
- **UFW 자동 구성**: 방화벽을 자동으로 설치 및 활성화하여 메일 통신에 필요한 포트(25, 110, 143, 465, 587, 993, 995, 80, 443)를 한 번에 자동 허용.
- **SSL 자동 생성**: 설치 시 기본 Self-signed SSL 인증서를 구성하며, 이후 Certbot 명령어 한 줄로 편리하게 Let's Encrypt 무료 보안 인증서로 교체할 수 있도록 안내.

---

## 🛠️ 신규 서버 세팅 방법

신규 서버(Debian/Ubuntu 계열)에서 다음의 단계로 한 번에 세팅을 완료할 수 있습니다.

### 1. 저장소 클론 및 이동
```bash
git clone https://github.com/mslopgk/kgpolsm-mail-setup.git
cd kgpolsm-mail-setup
```

### 2. 설정 수정 (선택 사항)
`setup_mailserver.sh` 스크립트 상단에 정의된 설정을 사용자의 환경에 맞게 변경합니다.
```bash
nano setup_mailserver.sh
```
- `DOMAIN`: 메일 서비스 도메인 (기본값: `kgpolsm.cloud`)
- `SUBDOMAIN`: 메일 서버 접속 서브도메인 (기본값: `mail.kgpolsm.cloud`)
- `DB_USER` / `DB_PASS`: 메일서버 내부 연동용 DB 계정 정보
- `ADMIN_MAIL_ID` / `ADMIN_PASSWORD`: 초기 생성할 어드민 메일 계정의 ID(아이디만 입력) 및 비밀번호 (기본값: `kgpolsm` / `dlwlgh44!!`)

### 3. 스크립트 실행
실행 권한을 부여하고 루트 권한으로 실행합니다.
```bash
chmod +x setup_mailserver.sh
sudo ./setup_mailserver.sh
```
*스크립트가 진행되는 동안 패키지 다운로드, 데이터베이스 구축, 메일 데몬 설정, Nginx 설정 및 Roundcube 구성이 완전히 자동으로 완료됩니다.*

### 4. Let's Encrypt SSL 적용 (강장 권장)
정상적으로 외부 메일을 송수신하기 위해 메일 도메인(`mail.domain.com`)에 SSL 보안 인증서를 입히는 것이 매우 중요합니다. 스크립트 실행 완료 후 아래 명령어로 SSL을 자동 발급받습니다.
```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx -d mail.kgpolsm.cloud
```

---

## 🖥️ Roundcube 관리자 화면 (Admin Panel)

1. 웹브라우저로 `https://mail.kgpolsm.cloud` (혹은 서버 IP)에 접속합니다.
2. 초기 관리자 이메일 계정(`kgpolsm@kgpolsm.cloud` / 비밀번호: `dlwlgh44!!`)으로 로그인합니다.
3. 메인 인터페이스 우측 상단 혹은 사이드 메뉴에 주입된 빨간색 **Admin Panel** 버튼을 클릭하면 새로운 가상 유저 추가/정지/삭제를 직관적으로 수행할 수 있습니다.

---

## 📂 파일 구성
- [setup_mailserver.sh](file:///C:/Users/user/kgpolsm-mail-setup/setup_mailserver.sh): 메일 스택 패키지 설치부터 DB 스키마 주입, 포트 방화벽 세팅, Nginx+PHP+Roundcube 설치 및 통합 설정을 담당하는 마스터 쉘 스크립트.
- [admin.php](file:///C:/Users/user/kgpolsm-mail-setup/admin.php): Roundcube 웹 내에서 가상 메일 유저를 관리하는 깔끔한 어드민 웹 인터페이스.
- [admin_button.php](file:///C:/Users/user/kgpolsm-mail-setup/admin_button.php): 현재 로그인된 사용자의 관리자 권한을 판별해 Roundcube UI에 Admin 바로가기 버튼을 주입하는 Roundcube PHP 플러그인.
- [setup_ufw.py](file:///C:/Users/user/kgpolsm-mail-setup/setup_ufw.py): 파이썬 기반 UFW 포트 개방 자동화 보조 스크립트.
