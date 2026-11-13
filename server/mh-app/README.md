# mh-app: шаблон домашнего конфига Mihomo

`templates/home.yaml` - снимок шаблона с DE3 (`/opt/mh-app/templates/home.yaml`), из него `build_configs.py` вместе с реестром узлов `nodes.json` собирает `home-config.yaml` и `work-config.yaml`.

Секреты заменены метками `__CONTROLLER_SECRET__`, `__SUB_TOKEN__`, `__LISTS_TOKEN__`. На DE3 лежит рабочий файл с настоящими значениями, поэтому симлинк на репозиторий невозможен: при правке на DE3 снимок обновляют вручную (скачать файл и повторить подстановку меток).

## Что поменялось 03.11.2026 (вечер)

- Группы: «Основные (Balancing)» и «Основные без Proton (Balancing)» (скрытые url-test, узлы из провайдера `az-vless`), «Резерв (Fallback)»; «Авто — …» - fallback над ними (timeout 150 мс). Поле `now` у «Авто» - имя внутренней группы, поэтому `server.py` и `router_watch.py` раскрывают его до конечного узла (с флагом); закрепление узла в карточке «Авто» идёт через скрытую группу.
- `ipv6: true` (корень и `dns`) и `IP-CIDR6,2000::/3` - в домашнем и рабочем конфигах одинаково (подмены для рабочего больше нет).
- `IP-CIDR6,2000::/3,Авто — самый быстрый,no-resolve` перед `MATCH`: голые IPv6-адреса идут в туннель (имена с AAAA сюда не попадают - `no-resolve`).
- Filmix, трекеры Лампы (megapeer, bitru, rutor, nnmclub, bigfangroup, anifilm, anilibria, kinozal) - правила на «Исключения (без Proton)» (прямой выход DE2): Proton по IPv6 режется CDN. TorrServer и пиры идут напрямую, в Mihomo их нет.
- Google по умолчанию - DE2.
- `server.py` и `router_watch.py` - снимки с DE3 (`/opt/mh-app/server.py`, `/opt/arr-stack/scripts/router_watch.py`), секретов в них нет (они читают `mihomo.secret`/`config.json`).

## Снимок шаблона без секретов

`./snapshot.sh` снимает `/opt/mh-app/templates/home.yaml` с DE3 и подставляет метки `__CONTROLLER_SECRET__`, `__SUB_TOKEN__`, `__LISTS_TOKEN__`. Так делать всегда: 03.11.2026 прямой `scp` занёс реальные значения в публичный репозиторий (история переписана, токены перевыпущены).

## Карточка «🌐 Режим IPv6 / IPv4»

Селектор наверху веб-интерфейса Mihomo, правило `AND,((IP-CIDR6,::/0,no-resolve),(NOT,((GEOIP,ru,no-resolve)))),🌐 Режим IPv6 / IPv4`
стоит после правил локальных сетей и действует только на IPv6-адреса вне РФ:

- `🔄 Авто Dual-Stack` - `PASS`: правила идут как обычно, `-4` выходит по IPv4 узла, `-6` по IPv6 (работает при `sniffer.override-destination: false`
  и `dns.enhanced-mode: normal`, на узле `sniffing.routeOnly: true`);
- `⚡ Приоритет IPv6 (Proton)` - весь внешний IPv6 в «Авто — самый быстрый»;
- `🚀 Приоритет IPv6 (Прямой VPS)` - весь внешний IPv6 в «Авто — без Proton»;
- `🛡️ Только IPv4` - внешний IPv6 отклоняется (`REJECT`), приложения переходят на IPv4.

Meta и Anthropic по IPv6 на узле сбрасываются (`xray-az-ipv4-domains.sh`), клиент сразу уходит на IPv4.
