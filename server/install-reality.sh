#!/bin/bash
# Установка VLESS + Reality (Xray) рядом с уже работающим сервером (AntiZapret, MTProxy и т.п.).
# Два входа:
#   8443 - выход в интернет с IP этого сервера;
#   8445 - выход через WireGuard-интерфейс (например, Proton), если задан PROXY_IFACE.
# Посторонний (сканер, браузер) на 8443/8445 видит ваш сайт-заглушку (LANDING_DOMAIN), а не прокси.
#
# Запуск (Ubuntu 22.04/24.04, Debian 12/13, под root):
#   LANDING_DOMAIN=site.example.com LANDING_BACKEND=127.0.0.1:8444 PROXY_IFACE=warp-vpn bash install-reality.sh
# LANDING_BACKEND - где уже отвечает HTTPS вашего сайта с настоящим сертификатом этого домена
# (своя nginx на 127.0.0.1:8444, заглушка MTProxyL selfmask и т.п.). Если сайта ещё нет - см. README, раздел 2.
set -e
: "${LANDING_DOMAIN:?укажите LANDING_DOMAIN}"
: "${LANDING_BACKEND:=127.0.0.1:8444}"
: "${PROXY_IFACE:=}"
: "${PORT_DIRECT:=8443}"
: "${PORT_PROXY:=8445}"
D=/opt/xray-reality
mkdir -p $D && cd $D

# 1. Xray
if [ ! -x $D/xray ]; then
	ARCH=$(uname -m); case $ARCH in x86_64) A=64;; aarch64) A=arm64-v8a;; *) echo "arch $ARCH?"; exit 1;; esac
	apt-get install -y -qq curl unzip >/dev/null
	curl -fsSL -o x.zip "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$A.zip"
	unzip -oq x.zip xray && rm -f x.zip && chmod +x xray
fi
$D/xray version | head -1

# 2. Ключи (создаются один раз, лежат в client.txt)
if [ ! -f $D/client.txt ]; then
	K=$($D/xray x25519)
	PRIV=$(echo "$K" | awk -F': ' '/Private/{print $2}')
	PUB=$(echo "$K" | awk -F': ' '/Public|Password/{print $2}' | head -1)
	UUID=$($D/xray uuid); SID=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
	printf '%s\n%s\n%s\n%s\n' "$UUID" "$PUB" "$SID" "$PRIV" > $D/client.txt; chmod 600 $D/client.txt
fi
UUID=$(sed -n 1p client.txt); PUB=$(sed -n 2p client.txt); SID=$(sed -n 3p client.txt); PRIV=$(sed -n 4p client.txt)

# 3. Конфиг
inb() { cat <<EOF
    {"tag": "$1", "port": $2, "protocol": "vless",
     "settings": {"clients": [{"id": "$UUID", "flow": "xtls-rprx-vision"}], "decryption": "none"},
     "streamSettings": {"network": "tcp", "security": "reality",
       "realitySettings": {"show": false, "dest": "$LANDING_BACKEND", "xver": 0,
         "serverNames": ["$LANDING_DOMAIN"], "privateKey": "$PRIV", "shortIds": ["$SID"]}},
     "sniffing": {"enabled": false}}
EOF
}
OUT_PROXY='{"tag": "proxy", "protocol": "freedom"}'
[ -n "$PROXY_IFACE" ] && OUT_PROXY="{\"tag\": \"proxy\", \"protocol\": \"freedom\", \"streamSettings\": {\"sockopt\": {\"interface\": \"$PROXY_IFACE\"}}}"
cat > $D/config.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
$(inb in-direct $PORT_DIRECT),
$(inb in-proxy $PORT_PROXY)
  ],
  "outbounds": [{"tag": "direct", "protocol": "freedom"}, $OUT_PROXY],
  "routing": {"rules": [{"type": "field", "inboundTag": ["in-proxy"], "outboundTag": "proxy"}]}
}
EOF
chmod 600 $D/config.json
$D/xray run -test -config $D/config.json

# 4. Служба
cat > /etc/systemd/system/xray-reality.service <<EOF
[Unit]
Description=Xray VLESS-Reality
After=network-online.target
[Service]
ExecStart=$D/xray run -config $D/config.json
Restart=on-failure
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable -q --now xray-reality && systemctl restart xray-reality
command -v ufw >/dev/null && ufw status | grep -q active && { ufw allow $PORT_DIRECT/tcp; ufw allow $PORT_PROXY/tcp; } >/dev/null

# 5. Проверка и данные для клиента
sleep 1; systemctl is-active xray-reality
echo "Посторонний видит сайт: $(curl -s -o /dev/null -m8 -w '%{http_code}' --resolve $LANDING_DOMAIN:$PORT_DIRECT:127.0.0.1 https://$LANDING_DOMAIN:$PORT_DIRECT/)"
HOST=${PUBLIC_HOST:-$(curl -s4 -m5 https://api.ipify.org)}
echo
echo "Ссылки для клиентов (v2rayNG, Hiddify, NekoBox, mihomo/Clash Meta):"
for p in "$PORT_DIRECT:direct" "$PORT_PROXY:proxy"; do
	echo "vless://$UUID@$HOST:${p%%:*}?type=tcp&security=reality&pbk=$PUB&fp=chrome&sni=$LANDING_DOMAIN&sid=$SID&flow=xtls-rprx-vision#$(hostname)-${p##*:}"
done
