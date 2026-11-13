# MTProxy (telemt) по IPv6

1. В `/opt/mtproxyl/mtproxy/config.toml` добавить (иначе `telemt` слушает только IPv4, несмотря на `listen_addr_ipv6 = "::"`):

       [network]
       ipv4 = true
       ipv6 = true

   затем `docker restart mtproxyl`. Проверено: NL2, DE1, LV1 (443) и FR1 (8443) - `req_pq_multi -> resPQ` по IPv6 проходит для всех секретов.
   Проверено по всем шести узлам (DE1 cdn, NL2 animal, LV1 static, FI1 media, DE4 bigboss - `linkbridged` это тот же telemt,
   конфиг `telemt.toml`, FR1 force :8443): resPQ по домену для всех 75 секретов проходит и по IPv4, и по IPv6.
   Прежний вывод «FI1 не отвечает по IPv6» был неверным: маршрут и шлюз v6 на FI1 исправны, `[2001:67c:4e8:f002::d]:80`
   открывается как на NL2. Предупреждения `family=V6 outage` от Middle Proxy есть и на NL2, и на FI1: v6-ME в telemt
   экспериментальный, он откатывается на v4-ME, клиентский IPv6 это не ломает.
2. Если включён `mtproxyl-zapret2`: `mtproxyl-zapret2-v6.sh` кладётся в `/usr/local/sbin/`, и drop-in
   `/etc/systemd/system/mtproxyl-zapret2.service.d/v6.conf`:

       [Service]
       ExecStartPost=/usr/local/sbin/mtproxyl-zapret2-v6.sh
       ExecStopPost=-/usr/sbin/nft delete table ip6 MTProtoL

   Это IPv6-копия таблицы `ip MTProtoL` с теми же очередями nfqws2 (200-201). Порт в скрипте - `PORT` (443; для FR1 8443).
   На узле, где zapret2 выключен (FR1), не включать.
3. AAAA для шести доменов MTProxy (DNS only, ttl 60) созданы через Cloudflare API: cdn, animal, static, media, bigboss, force.
   Для DE4 в AAAA указан `::d`, тот же адрес, что берёт `mtproxyl-zapret2-v6.sh` (первый глобальный).
