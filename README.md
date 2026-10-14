# VLESS-Reality + mihomo на роутере Netcraze / Keenetic

Как поднять на своих зарубежных серверах **VLESS + Reality** с сайтом-заглушкой и пустить через них
домашнюю сеть с помощью **mihomo** (Clash Meta) на роутере **Netcraze / Keenetic**: свои карточки
сервисов, автовыбор самого быстрого сервера, YouTube через zapret, выбор устройств политикой роутера.

```
устройство в политике «Mihomo» ─► Keenetic: DNS :53 → mihomo :7874, TCP → mihomo :7892
                                     │
                     mihomo: правила / карточки / «Авто»
                     ├─ российское и «остальное» ─► напрямую через провайдера
                     ├─ YouTube ─► напрямую + zapret (nfqws) на роутере
                     └─ заблокированное, ИИ, Telegram… ─► VLESS-Reality ─► ваш сервер ─► (прямой IP | Proton)
устройства вне политики ─► обычный интернет провайдера (mihomo их не трогает)
```

Почему так, а не WireGuard внутри mihomo: на роутере (aarch64) WireGuard в mihomo давал 120–180 Мбит/с,
VLESS-Reality — 240–390 Мбит/с в один поток и до 600+ в несколько. Reality к тому же выглядит как обычный
HTTPS к вашему сайту: сканер на порту сервера видит сайт с настоящим сертификатом.

---

## Быстрый старт (3 шага, ~15 минут)

**1. Сервер** (любой VPS за рубежом, Ubuntu/Debian, под root) — одна команда, домен и сайт не нужны:
```sh
curl -fsSL https://raw.githubusercontent.com/shax0491/reality_mihomo_netcraze/main/server/install-reality.sh | bash
```
В конце она напечатает две ссылки `vless://...` (они же в `/opt/xray-reality/links.txt`). Серверов может быть несколько —
повторите на каждом и соберите все ссылки.

**Проверить с телефона:** вставьте ссылку в Hiddify, v2RayTun или Happ — должен открыться, например, chatgpt.com.

**2. Роутер.** Один раз подготовить Entware (раздел 4 ниже: компоненты OPKG + флешка ext4), затем по SSH
(`ssh root@192.168.1.1 -p 222`) — одна команда со своими ссылками:
```sh
curl -fsSL https://raw.githubusercontent.com/shax0491/reality_mihomo_netcraze/main/router/install.sh | sh -s -- 'vless://ссылка1' 'vless://ссылка2'
```
Скрипт поставит mihomo, карточки сервисов, «Авто — самый быстрый», автозапуск, и напечатает адрес панели и пароль.

**3. Какие устройства пускать через mihomo:** веб-интерфейс роутера → «Приоритеты подключений» →
создать политику **Mihomo** и перетащить в неё нужные устройства (телефоны, ПК, ТВ). Через минуту они пойдут через
mihomo, остальные — как раньше, через провайдера.

Готово. Панель: `http://192.168.1.1:9090/ui` — там видно, какие сайты куда идут, и можно переключать серверы.
Всё ниже — подробности и ручная настройка (свой домен-заглушка, zapret для YouTube, списки, проверки).

---

# Подробно

## 1. Что понадобится

| Что | Примечание |
|---|---|
| Сервер за рубежом | Ubuntu 22.04/24.04 или Debian 12/13, публичный IPv4. Можно тот же, где уже стоит AntiZapret / MTProxy |
| Домен (необязательно) | для варианта с сайтом-заглушкой: на каждый сервер свой поддомен, A-запись на IP сервера (в Cloudflare — «DNS only», серое облако) |
| Сайт-заглушка (необязательно) | любая простая страница на этом домене с сертификатом Let's Encrypt (раздел 2) |
| Роутер | Netcraze / Keenetic с USB и KeeneticOS 4.x/5.x (проверено на Netcraze Ultra NC-1812, aarch64) |
| USB-флешка | от 4 ГБ, файловая система ext4 (для Entware) |

---

## 2. Сервер: сайт-заглушка

Reality при неверном ключе отдаёт посетителю **ваш** сайт. Он должен отвечать по HTTPS на локальном порту,
например `127.0.0.1:8444`, с настоящим сертификатом домена.

Если сайта ещё нет (nginx + certbot):

```bash
apt-get install -y nginx certbot
mkdir -p /var/www/landing && echo '<h1>Студия веб-разработки</h1>' > /var/www/landing/index.html
certbot certonly --webroot -w /var/www/html -d site.example.com -m you@example.com --agree-tos -n
cat > /etc/nginx/sites-available/landing <<'EOF'
server { listen 80; server_name site.example.com;
         location /.well-known/acme-challenge/ { root /var/www/html; }
         location / { return 301 https://site.example.com$request_uri; } }
server { listen 127.0.0.1:8444 ssl http2; server_name site.example.com;
         ssl_certificate     /etc/letsencrypt/live/site.example.com/fullchain.pem;
         ssl_certificate_key /etc/letsencrypt/live/site.example.com/privkey.pem;
         root /var/www/landing; }
# заход по IP или чужому имени - на сайт, а не обрыв (обрыв выдаёт прокси)
server { listen 80 default_server; return 301 https://site.example.com/; }
EOF
ln -sf /etc/nginx/sites-available/landing /etc/nginx/sites-enabled/ && nginx -t && systemctl reload nginx
```

Если на сервере стоит **MTProxyL** с Selfmask — заглушка уже есть на `127.0.0.1:8444`, используйте её.
Чтобы заход по IP тоже вёл на сайт: `mtproxyl selfmask nginx-config show > /tmp/n.conf`, в блоках
`default_server` замените `return 444;` на `return 301 https://ВАШ_ДОМЕН/;`, затем
`mtproxyl selfmask nginx-config write < /tmp/n.conf` и `yes y | mtproxyl selfmask nginx-config on`
(свой конфиг переживает обновления MTProxyL).

Проверка: `curl -sI https://site.example.com/` → `200`, `curl -sI http://IP_СЕРВЕРА/` → `301` на сайт.

---

## 3. Сервер: VLESS + Reality

```bash
curl -fsSLO https://raw.githubusercontent.com/shax0491/reality_mihomo_netcraze/main/server/install-reality.sh
LANDING_DOMAIN=site.example.com LANDING_BACKEND=127.0.0.1:8444 PROXY_IFACE=warp-vpn bash install-reality.sh
```

| Переменная | Значение |
|---|---|
| `LANDING_DOMAIN` | домен сайта-заглушки (он же SNI для клиентов) |
| `LANDING_BACKEND` | где отвечает HTTPS сайта, по умолчанию `127.0.0.1:8444` |
| `PROXY_IFACE` | интерфейс для второго входа: `warp-vpn` (Proton/WARP у AntiZapret) или пусто — тогда второй вход тоже с IP сервера |
| `PORT_DIRECT` / `PORT_PROXY` | порты входов, по умолчанию `8443` и `8445` |

Скрипт ставит Xray в `/opt/xray-reality`, создаёт ключи (`client.txt`: UUID, публичный ключ, short id),
конфиг (пример — [`server/config.example.json`](server/config.example.json)), службу `xray-reality`
и печатает две ссылки `vless://…` — для 8443 (выход с IP сервера) и 8445 (через `PROXY_IFACE`).

Проверка:
```bash
systemctl status xray-reality
curl -s -o /dev/null -w '%{http_code}\n' --resolve site.example.com:8443:127.0.0.1 https://site.example.com:8443/   # 200 = посторонний видит сайт
```

**AntiZapret на том же сервере.** Его защита от сканирования (`SCAN_PROTECTION`) банит источник, который за час
открывает больше 20 новых пар «IP-порт». Обычные клиенты Reality (одни и те же порты) под это не попадают;
не делайте с роутера массовых проб разных портов.

---

## 4. Роутер: компоненты и Entware

1. **Веб-интерфейс → Управление → Общие настройки → Изменить набор компонентов**, отметить:
   - «Поддержка открытых пакетов» (OPKG)
   - «Модули ядра подсистемы Netfilter»
   - «Пакет расширения Xtables-addons для Netfilter»

   Применить, роутер перезагрузится.
2. Флешку отформатировать в **ext4**, вставить в USB.
3. Скачать установщик Entware для своей архитектуры (Netcraze Ultra / Keenetic на ARM —
   `aarch64-installer.tar.gz`, на MIPS — `mipsel-installer.tar.gz`) с `https://bin.entware.net/`,
   в веб-интерфейсе создать на флешке папку `install` и положить туда файл.
4. **Управление → OPKG**: выбрать флешку → Сохранить. Через 2–3 минуты Entware установлен.
5. Вход по SSH: `ssh root@192.168.1.1 -p 222`, пароль `keenetic` — **сразу смените**: `passwd`.
6. Пакеты:
   ```sh
   opkg update
   opkg install curl ca-bundle iptables ip-full cron bind-dig jq
   /opt/etc/init.d/S10cron start
   ```
   Если `bin.entware.net` не открывается (провайдер/DNS), в веб-интерфейсе добавьте DNS-сервер для домена:
   `ip name-server 62.76.76.62 entware.net` (CLI) или через «Интернет-фильтры → DNS».

---

## 5. Роутер: mihomo

```sh
cd /opt/tmp
V=v1.19.32
curl -fsSL -o m.gz https://github.com/MetaCubeX/mihomo/releases/download/$V/mihomo-linux-arm64-$V.gz
gunzip -f m.gz && mv m /opt/sbin/mihomo && chmod +x /opt/sbin/mihomo && /opt/sbin/mihomo -v
mkdir -p /opt/etc/mihomo/providers /opt/etc/ndm/netfilter.d
```

Файлы из папки [`router/`](router) этого репозитория:

| Файл | Куда | Что делает |
|---|---|---|
| `config.example.yaml` | `/opt/etc/mihomo/config.yaml` | карточки, «Авто», DNS, правила, списки |
| `S99mihomo` | `/opt/etc/init.d/S99mihomo` | автозапуск |
| `90-mihomo.sh` | `/opt/etc/ndm/netfilter.d/90-mihomo.sh` | перехват устройств политики (DNS → 7874, TCP → 7892), QUIC |
| `macs.sh` | `/opt/etc/mihomo/macs.sh` | список MAC из политики «Mihomo» |
| `sync-devices.sh` | `/opt/etc/mihomo/sync-devices.sh` | раз в минуту переставляет правила, если поменялись устройства или Кинетик пересобрал iptables |
| `deploy.sh` | `/opt/etc/mihomo/deploy.sh` | безопасное применение конфига: тест → замена → перезапуск → откат при сбое |
| `quic-allow.txt` | `/opt/etc/mihomo/quic-allow.txt` | сети, куда QUIC идёт напрямую (видеосерверы YouTube) |
| `91-nfqws.sh`, `S98nfqws` | `/opt/etc/ndm/netfilter.d/`, `/opt/etc/init.d/` | zapret (nfqws) для YouTube — по желанию |
| `crontab.example` | дописать строки в `/opt/etc/crontab` | `sync-devices.sh` раз в минуту |

```sh
chmod +x /opt/etc/init.d/S99mihomo /opt/etc/ndm/netfilter.d/90-mihomo.sh /opt/etc/mihomo/*.sh
```

В `config.yaml` заменить:
- `<MIHOMO_SECRET>` — свой пароль панели (любая строка без пробелов);
- блок `proxy-providers` — ваш список серверов (раздел 6);
- `example.com` — ваши домены; списки `my-*` — свои (раздел 8).

Запуск и проверка:
```sh
/opt/etc/init.d/S99mihomo start
curl -s -x http://127.0.0.1:7890 https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip=|loc='
```

Панель: **http://192.168.1.1:9090/ui** (zashboard), адрес бэкенда `http://192.168.1.1:9090`, секрет из конфига.

---

## 6. Список серверов (подписка)

mihomo берёт серверы из `proxy-providers`. Проще всего — файл со всеми узлами (локальный или по ссылке):

```yaml
# /opt/etc/mihomo/providers/nodes.yaml  (или отдаётся по https с секретным токеном)
proxies:
  - {name: "🇩🇪 DE1 | VLESS Proton", type: vless, server: de1.example.com, port: 8445, uuid: <UUID>,
     network: tcp, tls: true, udp: true, flow: xtls-rprx-vision, servername: site1.example.com,
     client-fingerprint: chrome, reality-opts: {public-key: <PUB>, short-id: <SID>}}
  - {name: "🇩🇪 DE1 | VLESS прямой", type: vless, server: de1.example.com, port: 8443, uuid: <UUID>,
     network: tcp, tls: true, udp: true, flow: xtls-rprx-vision, servername: site1.example.com,
     client-fingerprint: chrome, reality-opts: {public-key: <PUB>, short-id: <SID>}}
```

`<UUID>`, `<PUB>`, `<SID>` — из `/opt/xray-reality/client.txt` сервера (строки 1–3) или из напечатанной ссылки.
В конфиге: `type: file` + `path: ./providers/nodes.yaml` (локально) или `type: http` + `url:` (по ссылке).

Карточки серверов собираются фильтром по имени (`filter: "DE1"`), «Авто — самый быстрый» — url-test по всем
`Proton`-вариантам: каждые 10 минут меряет задержку и переходит на лучший, если тот быстрее на 50 мс.

---

## 7. Какие устройства идут через mihomo

Только устройства из политики Кинетика **«Mihomo»**, остальные — обычный интернет провайдера.

Создать политику (один раз, CLI роутера: `ndmc -c '...'` или веб-интерфейс):
```
ip policy Mihomo
ip policy Mihomo description "Mihomo (VPN)"
ip policy Mihomo permit global <ВАШ_WAN, например XGigabitEthernet0>
system configuration save
```
Дальше: **Приоритеты подключений → Mihomo (VPN) → добавить устройство**. Правила включаются
в течение минуты (`sync-devices.sh`), снятие — так же. Уже открытые соединения устройства остаются
в mihomo, пока не закроются.

---

## 8. Списки сайтов

| Правило | Куда |
|---|---|
| `my-vpn` / `my-direct` / `my-block` | ваши личные списки — самый высокий приоритет |
| карточки сервисов (YouTube, Telegram, ИИ, Discord, Google, Instagram, WhatsApp, X, TikTok, Netflix…) | своя карточка, выбор сервера в панели |
| ваши include/exclude-hosts AntiZapret | «Заблокированное в РФ» / напрямую |
| реестр блокировок (antifilter + community + bol-van), itdoginfo, GeoSite `ru-blocked`, `refilter` | «Заблокированное в РФ» |
| GeoSite `category-ru`, GeoIP `ru`, списки roscomvpn | напрямую |
| всё остальное | «Остальной интернет» (по умолчанию напрямую) |

Полный реестр (~1,5 млн доменов) удобно собирать на сервере в компактный `.mrs`:
```bash
cat domains.lst | sed 's/^/+./' > full.txt
mihomo convert-ruleset domain text full.txt az-full.mrs
```
и подключать `type: http, format: mrs, behavior: domain, interval: 86400` — mihomo на роутере держит его в ~120 МБ памяти.

---

## 9. QUIC, YouTube и телефоны

- mihomo перехватывает только **TCP**. Приложения на телефонах (Gemini, ChatGPT, Claude, Google) часто
  ходят по **QUIC (UDP 443)** — такой трафик ушёл бы напрямую с российского IP. Поэтому `90-mihomo.sh`
  **отклоняет QUIC** устройств политики ко всему, кроме видеосерверов YouTube (`quic-allow.txt`):
  приложение сразу переходит на TCP, а TCP идёт через mihomo.
- QUIC к YouTube идёт напрямую через zapret. Правило nfqws стоит в **mangle POSTROUTING**, а не FORWARD:
  иначе второй пакет QUIC Initial уходит мимо очереди через аппаратное ускорение (FASTNAT) Кинетика.

---

## 10. Проверки

```sh
# какие устройства перехватываются
sh /opt/etc/mihomo/macs.sh
iptables -t nat -S MIHOMO | grep -c REDIRECT
# DNS не течёт: подсеть в ответе должна быть сетью вашего сервера/Proton, а не провайдера
curl -s -H "Authorization: Bearer <MIHOMO_SECRET>" "http://127.0.0.1:9090/dns/query?name=whoami.ds.akahelp.net&type=TXT"
# скорость через mihomo
curl -s -o /dev/null -x http://127.0.0.1:7890 -H 'User-Agent: Mozilla/5.0' -H 'Referer: https://speed.cloudflare.com/' \
     -w '%{speed_download}\n' 'https://speed.cloudflare.com/__down?bytes=25000000'
```

Изменение конфига — только через `deploy.sh`:
```sh
cp /opt/etc/mihomo/config.yaml /tmp/mihomo-new.yaml && vi /tmp/mihomo-new.yaml && sh /opt/etc/mihomo/deploy.sh
```

## Частые проблемы

| Симптом | Причина / решение |
|---|---|
| Устройство не идёт через mihomo | его нет в политике «Mihomo» или у телефона «случайный MAC» для этой сети — отключите в настройках Wi-Fi |
| Сайты открываются, приложения ИИ на телефоне — нет | QUIC мимо mihomo, см. раздел 9 |
| После перезагрузки нет перехвата | проверить cron (`/opt/etc/init.d/S10cron start`) и `sync-devices.sh` вручную |
| В имени группы запятая — конфиг не применяется | в именах групп mihomo нельзя запятые |
| Панель показывает MetaCubeXD вместо zashboard | задать `external-ui-url` (есть в примере) |
