<div align="center">

# openwrt-tailscale-oneliner

<br>

[![GitHub](https://img.shields.io/badge/GITHUB-repo-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/ASoba17/openwrt-tailscale-oneliner)
[![OpenWrt](https://img.shields.io/badge/OPENWRT-25.12.4-00B5E2?style=for-the-badge&logo=openwrt&logoColor=white)](https://openwrt.org/)
[![Tailscale](https://img.shields.io/badge/TAILSCALE-mesh-1B6EE8?style=for-the-badge&logo=tailscale&logoColor=white)](https://tailscale.com/)
[![License](https://img.shields.io/badge/LICENSE-MIT-21B517?style=for-the-badge&logo=mit&logoColor=white)](./LICENSE)
[![Shell](https://img.shields.io/badge/SHELL-POSIX_`sh`-2E2E2E?style=for-the-badge&logo=gnu-bash&logoColor=white)](#)

<br>

_Одна вставка в SSH — Tailscale поднят на OpenWrt 25.12.4 и сшит с LAN._

<br>

</div>

---

## 🔗 <a id="описание"></a> Описание

Скрипт настраивает [Tailscale](https://tailscale.com/) на [OpenWrt 25.12.4](https://openwrt.org/) так, чтобы LAN роутера видела ваш Tailnet и наоборот.

Зачем: роутер с OpenWrt отлично подходит на роль edge-ноды Tailscale — он уже смотрит в интернет, держит локалку инициализированной и имеет стабильное питание. Этот скрипт делает конфигурацию **воспроизводимой** в одну вставку.

Ключевые свойства:

- **Идемпотентный** — повторный запуск не дублирует forwarding'и и не ломает конфиг
- **Безопасно падает** — прерывание на середине не оставляет UCI в полу-состоянии (либо старое, либо новое)
- **Минимум поверхности** — только UCI + `network`/`firewall`/system, без сторонних сервисов
- **Виден статус** — выводит `tailscale0` и `tailscale status` после применения

---

## 🔗 <a id="предусловия"></a> Предусловия

| Требование | Зачем |
|---|---|
| OpenWrt **25.12.4** | основная цель; другие свежие сборки должны работать (см. таблицу совместимости ниже) |
| Пакет `tailscale` | нужен бинарьник и init-скрипты |
| SSH-доступ под **root** | UCI и перезапуск сервисов |

Установите Tailscale на роутер один раз перед запуском:

```sh
apk update
apk add tailscale
```

---

## 🔗 <a id="что-делает"></a> Что делает скрипт

Скрипт идёт по пяти шагам — каждый атомарен и виден в выводе:

| Шаг   | Действие                                                   |
|-------|------------------------------------------------------------|
| 1/5   | Создаёт сетевой интерфейс `tailscale0`                      |
| 2/5   | Создаёт firewall-зону `tailscale` с `input=ACCEPT`          |
| 3/5   | Добавляет двусторонний forwarding `lan ↔ tailscale`          |
| 4/5   | Включает IPv4 forwarding (`ip_forward=1`)                   |
| 5/5   | Коммитит UCI и перезапускает `network`/`firewall`           |

Топология после применения:

```
       ┌───────────────────────────┐
       │      OpenWrt роутер       │
       │                           │
       │  [lan zone] ⇄ [tailscale zone] │
       │       ▲             ▲     │
       │       │             │     │
       └───┬───┘         ┌───┴─────┘
           │             │
       LAN (192.168.x/24)   tailscale0 (100.x/32)
                                │
                                ▼  WireGuard/QUIC
                          Tailscale mesh
```

---

## 🔗 <a id="установка"></a> Установка

### Вариант A: однострочник по сети вашего роутера

```sh
ssh root@192.168.1.1 -- sh -c "$(curl -fsSL https://raw.githubusercontent.com/ASoba17/openwrt-tailscale-oneliner/main/tailscale-setup.sh)"
```

### Вариант B: ручная вставка

1. `cat tailscale-setup.sh` на своём ноуте
2. Скопируйте содержимое
3. `ssh root@192.168.1.1`
4. Вставьте скопированное и нажмите Enter

### Авторизация

Сразу после отработки (в том же SSH):

```sh
tailscale up
```

> Если в браузере будет окно `https://login.tailscale.com/...` — откройте его и подтвердите добавление узла.

---

## 🔗 <a id="использование"></a> Использование

После `tailscale up` можно поднять возможности:

```sh
# Сделать роутер exit-нодой (трафик клиентов пойдёт через домашний канал)
tailscale up --advertise-exit-node

# Анонсировать LAN-подсеть в tailnet (чтобы другие пиры видели LAN-устройства)
tailscale up --advertise-routes=192.168.1.0/24
```

Подтвердите маршруты / exit-node в [Tailscale admin](https://login.tailscale.com/admin/machines) — без approve они не активируются.

---

## 🔗 <a id="проверка"></a> Проверка

```sh
# интерфейс должен быть UP
ip -br addr show tailscale0

# зона tailscale + два forwarding'а
uci show firewall | grep -E 'zone|forwarding'

# ip_forward
uci get system.@system[0].ip_forward     # → 1

# работа Tailscale
tailscale status
tailscale ping <любой-другой-пир-tailnet>
```

---

## 🔗 <a id="откат"></a> Откат

Если хочется отменить всё и вернуть «как было»:

```sh
uci -q delete network.tailscale
uci -q delete firewall.tailscale
for fw in $(uci show firewall | awk -F'=' '/=forwarding$/{print $1}'); do
  idx="${fw#firewall.@forwarding[}"; idx="${idx%]}"
  src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
  dst=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
  case "${src}:${dst}" in
    "lan:tailscale"|"tailscale:lan") uci delete firewall.@forwarding[$idx] ;;
  esac
done
uci set system.@system[0].ip_forward='0'
uci commit network firewall system
/etc/init.d/network restart
/etc/init.d/firewall restart
```

---

## 🔗 <a id="совместимость"></a> Совместимость

| OpenWrt   | Результат | Комментарий |
|-----------|-----------|-------------|
| 25.12.4   | ✅ основная цель | разрабатывается и тестируется здесь |
| 24.10.x   | ✅ должно работать | `uci` API стабилен |
| 23.05+    | ⚠️ должно работать | возможны мелкие изменения в `/etc/init.d/` |
| < 22.03   | ❓ не тестировалось | откройте issue с логом |

Tailscale-пакет требует архитектуры, для которой он собран (`x86_64`, `aarch64`, `mipsel`/`mips` для многих SOHO-роутеров). Проверяйте в [официальном репозитории пакетов](https://github.com/adyanth/openwrt-tailscale).

---

## 🔗 <a id="безопасность"></a> Безопасность

- Создаётся зона `tailscale` со `input=ACCEPT` — это стандартный паттерн, но **в вашем threat model может быть слишком широко**. Если нужно ограничить — после запуска отредактируйте `firewall.@zone[?name='tailscale']` (`input`/`forward` → `REJECT`/`DROP`) и добавьте конкретные правила.
- Скрипт **не** настраивает Tailscale ACL — за это отвечает [админка tailnet](https://login.tailscale.com/access). Настройте access-control отдельно.
- `tailscale0` создаётся только после первого `tailscale up`. До этого скрипт всё равно применит всю UCI-часть (и это нормально).
- Не выставляйте admin-интерфейс `OpenWrt` (`http://192.168.1.1`) в публичный WAN — оставьте LAN-only.

Сообщения о безопасности — через [GitHub Security Advisories](../../security/advisories/new) (вкладка **Security** → **Advisory**).

---

## 🔗 <a id="дисклеймер"></a> Дисклеймер

Материалы этого репозитория публикуются в образовательных и обучающих целях. Используйте на свой страх и риск, соблюдайте законы вашей страны и правила сетей, к которым подключаетесь. Автор не несёт ответственности за нецелевое использование.

---

## 🔗 <a id="лицензия"></a> Лицензия

[MIT](./LICENSE) — делайте что хотите, но без гарантий.

<br>

<div align="center">

<sub>сделано для того чтобы OpenWrt+Tailscale вставал одной вставкой 🐉</sub>

</div>
