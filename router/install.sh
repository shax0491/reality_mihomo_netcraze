#!/bin/sh
# Установка mihomo на Netcraze / Keenetic (Entware) одной командой.
#   curl -fsSL https://raw.githubusercontent.com/shax0491/reality_mihomo_netcraze/main/router/install.sh | sh -s -- 'vless://...' 'vless://...'
# Аргументы - ссылки vless:// (их печатает server/install-reality.sh). Можно вместо них ссылку на подписку:
#   ... | SUB_URL='https://ваш-сервер/sub.txt' sh
# Повторный запуск на настроенном роутере ничего не трогает; FORCE=1 - переустановить (старый конфиг -> config.yaml.old).
set -e
REPO=https://raw.githubusercontent.com/shax0491/reality_mihomo_netcraze/main/router
V=${MIHOMO_VERSION:-v1.19.32}
M=/opt/etc/mihomo
say() { printf '\n== %s\n' "$*"; }

[ -x /opt/bin/opkg ] || { echo "Нет Entware: сначала раздел «Роутер: Entware» в README"; exit 1; }
if [ -f $M/config.yaml ] && [ "$FORCE" != 1 ]; then
	echo "mihomo уже настроен ($M/config.yaml). Переустановить: FORCE=1"; exit 1
fi
[ $# -gt 0 ] || [ -n "$SUB_URL" ] || { echo "Передайте ссылки vless:// аргументами или SUB_URL=..."; exit 1; }

say "Пакеты Entware"
opkg update >/dev/null
opkg install curl ca-bundle iptables ip-full cron jq </dev/null >/dev/null

say "mihomo $V"
case $(uname -m) in
	aarch64) A=arm64 ;;
	armv7l) A=armv7 ;;
	mips) A=mips-softfloat ;;
	mipsel|mipsle) A=mipsle-softfloat ;;
	*) echo "Неизвестная архитектура $(uname -m)"; exit 1 ;;
esac
curl -fsSL -o /opt/tmp/m.gz "https://github.com/MetaCubeX/mihomo/releases/download/$V/mihomo-linux-$A-$V.gz"
gunzip -f /opt/tmp/m.gz && mv /opt/tmp/m /opt/sbin/mihomo && chmod +x /opt/sbin/mihomo
/opt/sbin/mihomo -v | head -1

say "Файлы"
mkdir -p $M/providers /opt/etc/ndm/netfilter.d
[ -f $M/config.yaml ] && cp $M/config.yaml $M/config.yaml.old
get() { curl -fsSL -o "$2" "$REPO/$1"; }
get config.simple.yaml $M/config.yaml
get S99mihomo /opt/etc/init.d/S99mihomo
get 90-mihomo.sh /opt/etc/ndm/netfilter.d/90-mihomo.sh
for f in macs.sh sync-devices.sh deploy.sh quic-allow.txt; do get $f $M/$f; done
chmod +x /opt/etc/init.d/S99mihomo /opt/etc/ndm/netfilter.d/90-mihomo.sh $M/*.sh
for f in my-block my-block-ips my-direct my-direct-ips my-vpn my-vpn-ips; do [ -f $M/providers/$f.txt ] || : > $M/providers/$f.txt; done

say "Серверы"
if [ -n "$SUB_URL" ]; then
	# подписка по ссылке: провайдер становится http и обновляется раз в час
	awk -v u="$SUB_URL" '!d && /^    type: file$/ {print "    type: http"; print "    url: \"" u "\""; print "    interval: 3600"; d=1; next} {print}' \
		$M/config.yaml > /opt/tmp/c.yaml && mv /opt/tmp/c.yaml $M/config.yaml
fi
: > $M/servers.txt
for l in "$@"; do echo "$l" >> $M/servers.txt; done
echo "в servers.txt: $(grep -c '^vless://' $M/servers.txt) ссылок"

SECRET=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
sed -i "s/<MIHOMO_SECRET>/$SECRET/" $M/config.yaml

say "Проверка конфига"
/opt/sbin/mihomo -d $M -t -f $M/config.yaml | tail -1

say "Автозапуск"
grep -q sync-devices.sh /opt/etc/crontab 2>/dev/null || echo '*/1 * * * * root /opt/etc/mihomo/sync-devices.sh' >> /opt/etc/crontab
/opt/etc/init.d/S10cron restart >/dev/null 2>&1 || true
/opt/etc/init.d/S99mihomo restart
sleep 5
$M/sync-devices.sh >/dev/null 2>&1 || true

say "Готово"
IP=$(ip -4 addr show br0 2>/dev/null | awk '/inet /{sub("/.*","",$2); print $2; exit}')
echo "Панель:  http://${IP:-192.168.1.1}:9090/ui   (адрес бэкенда http://${IP:-192.168.1.1}:9090, секрет $SECRET)"
echo "Дальше:  в веб-интерфейсе роутера создайте политику «Mihomo» и добавьте в неё устройства (README, шаг 3)."
