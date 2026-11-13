#!/bin/bash
# Списки для mihomo домашнего/рабочего роутера (раздаются nginx: https://de3.example.com/lists/<токен>/):
#   az-include / az-exclude (+ -ips) - ваши списки AntiZapret из панели (то, что правите на странице списков);
#   az-full - реестр блокировок, как у AntiZapret: antifilter + community.antifilter + bol-van/rulist,
#   поддомены, покрытые родителем, убраны. Формат .mrs (компактный бинарный mihomo).
# cron: user-списки каждые 30 мин, полный реестр раз в сутки (аргумент full).
set -o pipefail
O=/var/www/az-lists; W=/opt/az-lists; T=$(mktemp -d); trap "rm -rf $T" EXIT
cd /opt/AdminPanelAZ/backend && set -a && . ./.env 2>/dev/null; set +a
.venv/bin/python - "$T" <<PY || exit 1
import sys, os
from app.services import backup_scheduler as bs
from app.database import SessionLocal
cc = bs.collect_backup_config_contents(SessionLocal()) or {}
for k, v in cc.items(): open(os.path.join(sys.argv[1], k), "w").write(v)
PY
dom() { tr -d "\r" < "$1" | sed -E "s/#.*//; s/[[:space:]]//g" | tr A-Z a-z | sed -E "s/^(\+\.|\*\.|\.)//" | grep -E "^[a-z0-9-]+(\.[a-z0-9-]+)+$" | grep -vE "^[0-9.]+$" | sort -u | sed "s/^/+./"; }
ips() { tr -d "\r" < "$1" | sed -E "s/#.*//; s/[[:space:]]//g" | grep -E "^[0-9]+(\.[0-9]+){3}(/[0-9]+)?$" | sort -u; }
for n in include exclude; do
	[ -s $T/$n-hosts.txt ] && dom $T/$n-hosts.txt > $T/az-$n.txt && [ -s $T/az-$n.txt ] && mv -f $T/az-$n.txt $O/az-$n.txt
	[ -f $T/$n-ips.txt ] && ips $T/$n-ips.txt > $T/az-$n-ips.txt && mv -f $T/az-$n-ips.txt $O/az-$n-ips.txt
done
if [ "$1" = full ]; then
	ok=1
	for u in antifilter=https://antifilter.download/list/domains.lst community=https://community.antifilter.download/list/domains.lst bolvan=https://raw.githubusercontent.com/bol-van/rulist/main/reestr_hostname.txt; do
		curl -sf -m300 "${u#*=}" -o $T/src-${u%%=*}.txt || ok=0
	done
	if [ $ok = 1 ]; then
		cat $T/src-*.txt | tr -d "\r" | tr A-Z a-z | sed -E "s/^(\+\.|\*\.|\.)//; s/[[:space:]].*//" | grep -E "^[a-z0-9-]+(\.[a-z0-9-]+)+$" | grep -vE "^[0-9.]+$" \
		 | awk "{n=split(\$0,p,\".\"); r=p[n]; for(i=n-1;i>=1;i--) r=r\".\"p[i]; print r}" | LC_ALL=C sort -u \
		 | awk "prev!=\"\" && index(\$0, prev\".\")==1 {next} {prev=\$0; print}" \
		 | awk "{n=split(\$0,p,\".\"); r=p[n]; for(i=n-1;i>=1;i--) r=r\".\"p[i]; print r}" | sed "s/^/+./" > $T/full.txt
		N=$(wc -l < $T/full.txt)
		if [ "$N" -gt 500000 ] && $W/mihomo convert-ruleset domain text $T/full.txt $T/az-full.mrs >/dev/null 2>&1; then
			mv -f $T/az-full.mrs $O/az-full.mrs; echo "$(date -Is) az-full: $N доменов" >> $W/build.log
		else echo "$(date -Is) az-full: пропуск (N=$N)" >> $W/build.log; fi
	else echo "$(date -Is) az-full: источник недоступен, оставлена прошлая версия" >> $W/build.log; fi
fi
# реклама/трекеры - тот же список, что режет DNS AntiZapret на узлах (ANTIZAPRET_ADBLOCK): AdGuard DNS filter + OISD small + списки форка
# + ваши include/exclude-adblock-hosts из панели. VLESS/mihomo DNS узла не используют, поэтому режем правилом REJECT в mihomo.
# az-adblock.mrs - что блокировать, az-adblock-allow.mrs - исключения (в правиле: AND(az-adblock, NOT az-adblock-allow) -> REJECT).
if [ "$1" = full ] || [ ! -s $O/az-adblock.mrs ]; then
	F=https://raw.githubusercontent.com/shax0491/AntiZapret-VPN_new/main/setup/root/antizapret/download
	aok=1
	curl -sf -m 120 https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt -o $T/ad-adguard.txt || curl -sf -m 120 https://cdn.jsdelivr.net/gh/AdguardTeam/AdGuardSDNSFilter@gh-pages/Filters/filter.txt -o $T/ad-adguard.txt || aok=0
	curl -sf -m 120 https://raw.githubusercontent.com/sjhgvr/oisd/main/domainswild2_small.txt -o $T/ad-oisd.txt || curl -sf -m 120 https://cdn.jsdelivr.net/gh/sjhgvr/oisd@main/domainswild2_small.txt -o $T/ad-oisd.txt || aok=0
	curl -sf -m 60 $F/include-adblock-hosts.txt -o $T/ad-fork-inc.txt; curl -sf -m 60 $F/exclude-adblock-hosts.txt -o $T/ad-fork-exc.txt
	if [ $aok = 1 ]; then
		{ sed -n '/\*/!s/^||\([^ ^]*\)\^.*$/\1/p' $T/ad-adguard.txt; cat $T/ad-oisd.txt $T/ad-fork-inc.txt $T/include-adblock-hosts.txt 2>/dev/null; } > $T/ad-inc.raw
		{ sed -n '/\*/!s/^@@||\([^ ^]*\)\^.*$/\1/p' $T/ad-adguard.txt; cat $T/ad-fork-exc.txt; echo; cat $T/exclude-adblock-hosts.txt 2>/dev/null; echo; cat $W/adblock-allow-extra.txt; } > $T/ad-exc.raw
		dom $T/ad-inc.raw > $T/ad-inc.txt; dom $T/ad-exc.raw > $T/ad-exc.txt
		N=$(wc -l < $T/ad-inc.txt)
		if [ "$N" -gt 50000 ] && $W/mihomo convert-ruleset domain text $T/ad-inc.txt $T/az-adblock.mrs >/dev/null 2>&1 \
		   && $W/mihomo convert-ruleset domain text $T/ad-exc.txt $T/az-adblock-allow.mrs >/dev/null 2>&1; then
			mv -f $T/az-adblock.mrs $O/az-adblock.mrs; mv -f $T/az-adblock-allow.mrs $O/az-adblock-allow.mrs
			echo "$(date -Is) az-adblock: $N доменов, исключений $(wc -l < $T/ad-exc.txt)" >> $W/build.log
		else echo "$(date -Is) az-adblock: пропуск (N=$N)" >> $W/build.log; fi
	else echo "$(date -Is) az-adblock: источник недоступен, оставлена прошлая версия" >> $W/build.log; fi
fi
# подсети, которые AntiZapret на узлах гонит в туннель (result/route-ips): Cloudflare, Fastly, Telegram, WhatsApp/Meta -
# тот же апстрим, что у узлов; за ними сидят многие сайты, которые «у АнтиЗапрета работали»
U=https://raw.githubusercontent.com/GubernievS/AntiZapret-VPN/main/setup/root/antizapret/download
rok=1; for f in cloudflare fastly telegram whatsapp; do curl -sf -m 60 "$U/$f-ips.txt" -o $T/r-$f.txt || rok=0; done
# IPv6-подсети тех же сервисов (+ Meta) из репозитория: нужны, когда mihomo отдаёт на узел чистый IPv6-адрес (sniffer без override-destination)
R6=https://raw.githubusercontent.com/shax0491/AntiZapret-VPN_new/main/setup/root/antizapret
: > $T/r6.txt
for f in cloudflare fastly telegram google; do curl -sf -m 60 "$R6/download/$f-ips6.txt" >> $T/r6.txt; echo >> $T/r6.txt; done
curl -sf -m 60 "$R6/config/include-ips6.txt" >> $T/r6.txt; echo >> $T/r6.txt
printf "2a03:2880::/32
2620:0:1c00::/40
2803:f800::/32
2405:b500::/32
2405:8100::/32
2606:4700::/32
2a06:98c0::/29
2c0f:f248::/32
" >> $T/r6.txt
ips6() { tr -d "" < "$1" | sed -E "s/#.*//; s/[[:space:]]//g" | tr A-Z a-z | grep -E "^[0-9a-f:]+:[0-9a-f:]*/[0-9]+$"; }
if [ $rok = 1 ]; then { for f in $T/r-*.txt; do ips $f; done; ips6 $T/r6.txt; } | sort -u > $T/az-route-ips.txt; [ -s $T/az-route-ips.txt ] && mv -f $T/az-route-ips.txt $O/az-route-ips.txt; fi
chmod 644 $O/* 2>/dev/null
