# MTProxy (telemt) по IPv6

1. В `/opt/mtproxyl/mtproxy/config.toml` добавить (иначе `telemt` слушает только IPv4, несмотря на `listen_addr_ipv6 = "::"`):

       [network]
       ipv4 = true
       ipv6 = true

   затем `docker restart mtproxyl`. Проверено: NL2, DE1, LV1 (443) и FR1 (8443) - `req_pq_multi -> resPQ` по IPv6 проходит для всех секретов.
   FI1 с этим параметром по IPv6 не отвечает (resPQ 0 из 16) - там оставлен только IPv4. DE4 - `linkbridged`, не telemt.

2. Если включён `mtproxyl-zapret2`: `mtproxyl-zapret2-v6.sh` кладётся в `/usr/local/sbin/`, и drop-in
   `/etc/systemd/system/mtproxyl-zapret2.service.d/v6.conf`:

       [Service]
       ExecStartPost=/usr/local/sbin/mtproxyl-zapret2-v6.sh
       ExecStopPost=-/usr/sbin/nft delete table ip6 MTProtoL

   Это IPv6-копия таблицы `ip MTProtoL` с теми же очередями nfqws2 (200-201). Порт в скрипте - `PORT` (443; для FR1 8443).
   На узле, где zapret2 выключен (FR1), не включать.
3. AAAA для доменов MTProxy добавляются в DNS отдельно.
