#!/bin/sh
# безопасное применение: новый конфиг проверяется отдельно, рабочий заменяется и mihomo перезапускается только если проверка прошла
cd /opt/etc/mihomo
if /opt/sbin/mihomo -d . -f /tmp/mihomo-new.yaml -t >/tmp/mihomo-test.log 2>&1; then
	cp config.yaml config.yaml.prev; cp /tmp/mihomo-new.yaml config.yaml; /opt/etc/init.d/S99mihomo restart >/dev/null; sleep 8
	pidof mihomo >/dev/null && echo "APPLIED, mihomo $(pidof mihomo)" || { cp config.yaml.prev config.yaml; /opt/etc/init.d/S99mihomo restart >/dev/null; echo "START FAILED - rolled back"; }
else
	echo "TEST FAILED - not applied:"; grep -iE "error|fail" /tmp/mihomo-test.log | head -3
fi
