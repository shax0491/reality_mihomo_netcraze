#!/bin/sh
# Режим «Только IPv6» режет IPv4 вне РФ: карточка «🌐 Режим IPv6 / IPv4» напрямую управляет только v6-правилом,
# v4-часть (скрытая группа) подтягиваем к карточке (cron раз в минуту; Mini App/бот меняют её сразу).
API=http://127.0.0.1:9090; H="Authorization: Bearer $(sed -n 's/^secret: "\(.*\)"/\1/p' /opt/etc/mihomo/config.yaml | head -1)"
enc() { printf '%s' "$1" | sed -e 's/ /%20/g' -e 's#/#%2F#g'; }
CARD="🌐 Режим IPv6 / IPv4"; V4G="🌐 v4-политика (синхронно с режимом)"
now=$(curl -s -m 5 -H "$H" "$API/proxies/$(enc "$CARD")" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
[ -z "$now" ] && exit 0
case "$now" in *"Только IPv6"*) want=REJECT;; *) want=PASS;; esac
cur=$(curl -s -m 5 -H "$H" "$API/proxies/$(enc "$V4G")" | sed -n 's/.*"now":"\([^"]*\)".*/\1/p')
[ "$cur" = "$want" ] || curl -s -m 5 -X PUT -H "$H" -d "{\"name\":\"$want\"}" "$API/proxies/$(enc "$V4G")"
