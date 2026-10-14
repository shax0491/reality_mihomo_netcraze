#!/bin/sh
# zapret на роутере: в NFQUEUE 301 только исходящие с самого роутера (OUTPUT) на WAN - это соединения mihomo DIRECT.
# Транзит сети (в т.ч. zapret-gw) идёт через FORWARD и сюда не попадает. Первые 6 пакетов соединения.
[ "$type" = "ip6tables" ] && exit 0
# как на zapret-gw: подставленные nfqws пакеты (метка 0x40000000) не отслеживаются (raw NOTRACK), и ядро не
# считает соединение испорченным из-за пакетов с "неправильным" seq (be_liberal) - иначе длинные потоки (видео) встают
K0=/lib/modules/$(uname -r)
for m in iptable_raw xt_CT; do lsmod | grep -q "^$m " || insmod $K0/$m.ko 2>/dev/null; done
sysctl -qw net.netfilter.nf_conntrack_tcp_be_liberal=1
if [ -z "$table" ] || [ "$table" = "raw" ] || [ "$table" = "mangle" ]; then
	# только TCP: поддельные QUIC от устройств сети должны пройти NAT (иначе уходят с адресом 192.168.x)
	/opt/sbin/iptables -w -t raw -D OUTPUT -m mark --mark 0x40000000/0x40000000 -j CT --notrack 2>/dev/null
	/opt/sbin/iptables -w -t raw -D OUTPUT -p tcp -m mark --mark 0x40000000/0x40000000 -j CT --notrack 2>/dev/null
	/opt/sbin/iptables -w -t raw -I OUTPUT -p tcp -m mark --mark 0x40000000/0x40000000 -j CT --notrack
fi
[ -n "$table" ] && [ "$table" != "mangle" ] && exit 0
K=/lib/modules/$(uname -r)
lsmod | grep -q "^xt_connbytes " || insmod $K/xt_connbytes.ko 2>/dev/null
IPT=/opt/sbin/iptables; WAN=eth4
CB="-m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes 1:6 -m mark ! --mark 0x40000000/0x40000000"
$IPT -w -t mangle -D OUTPUT -j NFQWS 2>/dev/null; $IPT -w -t mangle -D POSTROUTING -j NFQWS 2>/dev/null
$IPT -w -t mangle -F NFQWS 2>/dev/null || $IPT -w -t mangle -N NFQWS
pidof nfqws >/dev/null || pidof nfqws2 >/dev/null || exit 0
# multiport в прошивке нет - по правилу на порт
for p in 80 443; do $IPT -w -t mangle -A NFQWS -o $WAN -p tcp --dport $p $CB -j NFQUEUE --queue-num 301 --queue-bypass; done
$IPT -w -t mangle -A NFQWS -o $WAN -p udp --dport 443 $CB -j NFQUEUE --queue-num 301 --queue-bypass
$IPT -w -t mangle -I POSTROUTING -j NFQWS
