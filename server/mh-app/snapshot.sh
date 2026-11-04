#!/bin/bash
# Снимок шаблона с DE3 в репозиторий: реальные секрет контроллера и токены подписки/списков заменяются метками.
# Никогда не копируйте /opt/mh-app/../../router/config.example.yaml напрямую (так значения попали в публичный git 03.11.2026).
set -e
H=root@203.0.113.10; K=${1:-$HOME/Desktop/de_htb_claude}
ssh -i "$K" $H 'cd /opt/mh-app; SUB=$(cat sub.token); CTL=$(cat mihomo.secret); LST=$(cat /opt/az-lists/token);
  sed "s/$SUB/__SUB_TOKEN__/g; s/$CTL/__CONTROLLER_SECRET__/g; s/$LST/__LISTS_TOKEN__/g" ../../router/config.example.yaml' > "$(dirname "$0")/../../router/config.example.yaml"
! grep -qE '[0-9a-f]{16,}' "$(dirname "$0")/../../router/config.example.yaml" || { echo "в снимке остались длинные hex-значения - проверьте"; exit 1; }
