#!/bin/sh
# все MAC политики «Mihomo» из конфига Кинетика, без привязки к ARP (IPv6 устройству нужен и когда IPv4-запись ARP протухла)
ndmc -c "show running-config" 2>/dev/null | awk "/^ip hotspot/{h=1} h&&/^!/{h=0} h&&/ policy Mihomo\$/{print tolower(\$2)}" | sort -u
