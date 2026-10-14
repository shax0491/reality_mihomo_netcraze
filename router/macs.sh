#!/bin/sh
# mihomo только для устройств в политике Кинетика «Mihomo»; остальные идут к провайдеру
ndmc -c "show running-config" 2>/dev/null | awk '/^ip hotspot/{h=1} h&&/^!/{h=0} h&&/ policy Mihomo$/{print tolower($2)}' | while read m; do
	awk -v m=$m 'NR>1 && $3=="0x2" && $6=="br0" && tolower($4)==m {print m; exit}' /proc/net/arp
done | sort -u
