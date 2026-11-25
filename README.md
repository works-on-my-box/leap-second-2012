# Високосная секунда 30 июня 2012 года: баг ядра Linux в QEMU

В ночь на 1 июля 2012 года в сутки UTC вставили високосную секунду, 23:59:60. На серверах с ядром Linux того времени после неё простаивающие процессы начали занимать процессор: подсистема таймеров hrtimer не узнала, что часы отошли на секунду назад, и ожидания с таймаутом по реальному времени стали заканчиваться сразу. Нагрузка сама не проходила; снимала её команда `date -s "$(date)"` или перезагрузка. Этот репозиторий повторяет ту ночь одной командой: в QEMU загружается ядро Ubuntu 12.04, которое стояло у пользователей 30 июня 2012 года (3.2.0-26.41), часы гостя ставятся на 30.06.2012 23:59:35 UTC, ядру объявляется вставка секунды, и видно, как после полуночи растёт нагрузка и как `date -s` её снимает. Для сравнения — то же на первом исправленном ядре Ubuntu (3.2.0-29.46) и на современном ядре.

## Что нужно

- Linux x86-64. Проверено на Ubuntu 24.04; подойдёт и другой дистрибутив, где есть пакеты ниже и `script` из util-linux 2.35 или новее.
- QEMU (`qemu-system-x86_64`), gcc со статической libc, python3, curl. KVM не нужен: гость работает в программной эмуляции.
- Около 2 ГБ свободной памяти (гостю — 768 МБ, в прогонах с Java и MySQL — 1024 МБ).
- Диск: около 250 МБ для прогона по умолчанию, около 900 МБ для всех прогонов (скачанные пакеты, распакованные ядра и initramfs в `work/`).
- Сеть при первом запуске: пакеты Ubuntu 12.04 скачиваются с launchpad.net и old-releases.ubuntu.com, для прогонов `k*-selftest` — ещё исходник теста ядра с git.kernel.org; каждый файл сверяется по sha256 (`packages.sha256`). Дальше всё берётся из `work/`.
- root не нужен, если пакеты уже стоят.
- Время: прогон по умолчанию — около минуты работы гостя; первый запуск со скачиванием на чистой Ubuntu 24.04 занял от 1,5 до 3,5 минуты (всё сверх минуты — скачивание, в основном ядра: 38 МБ с launchpad.net). Все прогоны подряд (`./run.sh all`) — около 18 минут, из них шесть — `k26-nofix`.

## Как запустить

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends qemu-system-x86 gcc libc6-dev python3 curl ca-certificates git

git clone https://github.com/works-on-my-box/leap-second-2012.git
cd leap-second-2012
./run.sh            # ядро той ночи, 3.2.0-26: секунда, нагрузка, снятие командой date
./run.sh k29-load   # то же на исправленном ядре 3.2.0-29: нагрузки нет
```

`run.sh` сам проверяет, всего ли хватает, и называет недостающие пакеты. Консоль гостя видна по ходу прогона; каждый запуск пишет записи в новый каталог `out/<дата-время>/`: `ИМЯ.txt` — чистый текст, `ИМЯ.typescript` и `ИМЯ.timing` — для повтора в реальном времени:

```bash
scriptreplay --log-timing out/…/k26-load.timing --log-out out/…/k26-load.typescript
```

Записи, снятые на облачном сервере (2 vCPU, 4 ГБ, Ubuntu 24.04, без KVM), лежат в `recordings/` — их можно посмотреть, ничего не запуская. Записи прогонов `k26-softirq`, `k29-softirq`, `k26-selftest` и `k29-selftest` сняты на другой машине: в контейнере Docker с Ubuntu 24.04 на ноутбуке (QEMU 8.2.2, тоже без KVM); `recordings/host.txt` описывает только сервер.

## Что вы увидите

Сценарий печатает каждую команду с приглашением, как в терминале. Строки `[load]` раз в секунду печатает программа нагрузки: два потока, каждый в цикле ждёт 100 мс; в норме это 19–20 пробуждений в секунду. Выдержка из `recordings/k26-load.txt`:

```
[load] 23:59:57 UTC  threads=2  wakeups/s=19        cpu=  0.8%
[load] 23:59:58 UTC  threads=2  wakeups/s=18        cpu=  0.6%
[load] 23:59:59 UTC  threads=2  wakeups/s=15709     cpu= 54.9%
[load] 00:00:00 UTC  threads=2  wakeups/s=44009     cpu=109.4%
[load] 00:00:01 UTC  threads=2  wakeups/s=49851     cpu=106.8%
…
root@probe:~# dmesg | grep -i -E "leap|clock:"
[   28.294284] Clock: inserting leap second 23:59:60 UTC
…
---------- ПОСЛЕ вставленной секунды ----------

root@probe:~# top -b -n 2 -d 1 | awk '/^top -/{n++} n==2' | head -n 11
top - 00:00:15 up 0 min,  0 users,  load average: 0.92, 0.21, 0.07
Tasks:  45 total,   1 running,  44 sleeping,   0 stopped,   0 zombie
Cpu(s): 31.1%us, 66.7%sy,  0.0%ni,  0.0%id,  0.0%wa,  0.0%hi,  2.2%si,  0.0%st
…
  PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
   85 0         20   0 17628  256  212 S  133  0.0   0:18.56 timedwait-load
    3 0         20   0     0    0    0 S   36  0.0   0:06.21 ksoftirqd/0
   10 0         20   0     0    0    0 S   31  0.0   0:06.75 ksoftirqd/1
…
[load] 00:00:23 UTC  threads=2  wakeups/s=50316     cpu=114.5%

root@probe:~# date -s "$(date)"
Sun Jul  1 00:00:24 UTC 2012
[load] 00:00:24 UTC  threads=2  wakeups/s=338       cpu=  0.7%
[load] 00:00:25 UTC  threads=2  wakeups/s=19        cpu=  0.7%
```

Сколько пробуждений в секунду получится у вас, зависит от скорости эмуляции: на сервере записей — 37–55 тысяч, в контейнере Docker на ноутбуке — около 21 тысячи. Важен скачок с 19 в секунду и 0 % простоя машины, пока не выполнена `date -s`.

## Прогоны

`./run.sh ИМЯ` (можно несколько имён подряд). Числа — из записей в `recordings/`.

| Прогон | Ядро гостя | До полуночи | После вставленной секунды | После `date -s "$(date)"` |
|---|---|---|---|---|
| `k26-load` (по умолчанию) — программа нагрузки | 3.2.0-26.41 | 15–21 пробуждений/с, 0,6–2,1 % ЦП | 37 627–54 928 пробуждений/с, процесс 87–121 %; `top` — 0,0 % простоя | 19/с, 0,7–1,2 % |
| `k29-load` — то же | 3.2.0-29.46 | 15–19/с, 0,5–2,1 % | 3–19/с, 0,2–1,4 %; `top` — 99,5 % простоя | 9–19/с, 0,5–0,8 % |
| `k26-nofix` — пять минут без вмешательства, потом `date -s` | 3.2.0-26.41 | 17–19/с, 0,5–2,0 % | все пять минут 36 878–57 379/с, 99,6–133,9 %; load average к 5-й минуте 3,03 | 17–19/с, 0,6–1,2 % |
| `modern` — ядро хоста | 6.8.0-151 | 15–19/с, 0,7–2,0 % | 3–19/с, 0,2–1,3 %; та же строка ядра о секунде | 19/с, 0,7–1,0 % |
| `k26-java` — простаивающий `rmiregistry` из OpenJDK 6 (Ubuntu 12.04) | 3.2.0-26.41 | процесс 0–2 % | 89–141 % | 1 % |
| `k29-java` — то же | 3.2.0-29.46 | 0–2 % | 0–2 % | 1–2 % |
| `k26-mysql` — простаивающий `mysqld` 5.5.22 из Ubuntu 12.04, ни одного запроса | 3.2.0-26.41 | 0–1 % | 133–190 % (одна строка — 238 %) | 0–1 % |
| `k29-mysql` — то же | 3.2.0-29.46 | 0–1 % | 0–1 % | 0–1 % |
| `k26-softirq` — то же, что `k26-load`, плюс `/proc/softirqs`: прирост счётчика `HRTIMER` (CPU0+CPU1) за 5 секунд | 3.2.0-26.41 | 17–19/с, 0,4–1,3 %; `HRTIMER` +1 | 21 088–28 011/с, 103–122 %; `top` — 0,0 % простоя, `ksoftirqd/0` и `ksoftirqd/1` — 38 и 40 %; `HRTIMER` +136 579 | 19/с, 0,3–0,8 %; `HRTIMER` +1 |
| `k29-softirq` — то же | 3.2.0-29.46 | 17–19/с, 0,5–1,6 %; `HRTIMER` +2 | 3–19/с, 0,2–0,7 %; `HRTIMER` +1 | 15–19/с, 0,4–0,6 %; `HRTIMER` +1 |
| `k26-selftest` — тест ядра `leap-a-day -i 1`: одна вставка секунды | 3.2.0-26.41 | | `Error: Early timer expiration!`, `ERROR: hrtimer early expiration failure observed.`, код выхода 1 | |
| `k29-selftest` — то же | 3.2.0-29.46 | | `Leap complete` без ошибок, код выхода 0 | |
| `all` — все по очереди | | | | |

Прогон `modern` загружает ядро самой машины (`/boot/vmlinuz-$(uname -r)`). На Ubuntu этот файл читает только root; если `run.sh` не может его прочитать, он подскажет, как скопировать ядро к себе и указать его переменной `MODERN_KERNEL`.

Прогоны `k*-softirq` показывают, что в это время делает ядро. Строка `HRTIMER` в `/proc/softirqs` — сколько раз на каждом процессоре выполнялось отложенное прерывание (softirq) подсистемы hrtimer. Сценарий читает её до полуночи, примерно через 10 секунд после вставленной секунды и после `date -s`, каждый раз дважды с паузой 5 секунд. На 3.2.0-26.41 после секунды счётчик вырос на 136 579 за 5 секунд — около 27 тысяч в секунду, а программа нагрузки в те же секунды просыпалась 21–28 тысяч раз в секунду. После `date -s` и на 3.2.0-29.46 прирост — 1–2 за 5 секунд.

Прогоны `k*-selftest` запускают тест ядра `leap-a-day` из `tools/testing/selftests/timers` (автор — John Stultz, автор исправления 2012 года) на одну вставку секунды. Тест сам ставит часы за 10 секунд до полуночи UTC, объявляет секунду и после неё проверяет, не сработали ли таймеры раньше срока. `run.sh` скачивает его исходник и два заголовка с git.kernel.org (тег v7.3) и сверяет sha256; в репозиторий тест не входит, его лицензия — GPLv2. На 3.2.0-26.41 (`recordings/k26-selftest.txt`):

```
Error: Early timer expiration! (Should be 1341100800)
…
Error: Timer seeing incorrect NTP state? (Should be TIME_WAIT)
…
ERROR: hrtimer early expiration failure observed.
Leap complete
Errors observed
```

и код выхода 1; на 3.2.0-29.46 — `Leap complete` без ошибок и код 0.

Проценты в строках `[java]` и `[mysqld]` — тики процессора за один проход цикла замера (`sleep 1` и чтение `/proc/PID/stat`). Под нагрузкой проход длится дольше секунды (в записи видны пропущенные секунды), поэтому встречаются значения выше 200 % при двух процессорах гостя. Строки `[load]` считаются по монотонным часам, и этого искажения у них нет.

## Как устроен стенд

- **Гость — не установленная система.** Ядро — из пакета `linux-image` Ubuntu 12.04: 3.2.0-26.41 вышло в обновления 28.06.2012 и стояло у пользователей в ту ночь; 3.2.0-29.46 — первое исправленное, в обновлениях с 10.08.2012. Пользовательская часть — initramfs из пакетов 12.04: libc6 2.15, bash 4.2, coreutils 8.13 (GNU `date`), procps (`top`), sysstat (`mpstat`), busybox; для `k*-java` — ещё OpenJDK 6, для `k*-mysql` — MySQL 5.5.22. Пакеты и их sha256 — в `packages.sha256`.
- **`src/init`** монтирует `/proc`, `/sys`, `/dev`, `/tmp`, по параметру ядра `demo=…` запускает сценарий и в конце перезагружает гостя; QEMU запущен с `-no-reboot` и на этом выходит.
- **`src/demo*.sh`** — сценарии: ставят часы на 30.06.2012 перед полуночью (`date -u -s`), объявляют секунду, запускают нагрузку, снимают `top`, `mpstat`, `/proc/loadavg` до полуночи, после секунды и после `date -s "$(date)"`. `demo-softirq.sh` в тех же трёх точках читает ещё `/proc/softirqs`, `demo-selftest.sh` вместо нагрузки запускает тест ядра `leap-a-day -i 1`.
- **`src/leapins.c`** объявляет ядру вставку секунды в ближайшую полночь UTC: системный вызов `adjtimex` с `ADJ_STATUS` и флагом `STA_INS` — тем же вызовом это делает ntpd. `leapins show` показывает состояние ядра (`TIME_INS` до полуночи, `TIME_WAIT` после), `leapins offset` — разницу `CLOCK_REALTIME − CLOCK_MONOTONIC`.
- **`src/timedwait-load.c`** — N потоков (по умолчанию 2), каждый в цикле ждёт условную переменную (`pthread_cond_timedwait`) с таймаутом 100 мс; по умолчанию условная переменная меряет таймаут по `CLOCK_REALTIME`. Раз в секунду программа печатает число пробуждений и загрузку процессора процессом.
- **`src/adjtimex-syscall.c`** — замена `adjtimex()` для теста `leap-a-day`: прямой системный вызов, как в glibc 2.15. Обёртка новой glibc идёт через `clock_adjtime`, а в ядрах 3.2 `clock_adjtime` не возвращает структуру, если результат не 0 (`TIME_INS`, `TIME_OOP`, `TIME_WAIT`), и тест не видел бы ни времени, ни состояния. Подключается ключом компоновщика `-Wl,--wrap=adjtimex`; исходник теста не меняется.
- **`scripts/`**: `build-initrd.sh` собирает initramfs, `mkcpio.py` пакует его без root, `run-vm.sh` запускает QEMU (`-accel tcg,thread=multi -cpu qemu64 -smp 2`, без сети, консоль — последовательный порт), `clean-typescript.py` делает из записи `script` чистый текст.
- **`run.sh`** проверяет зависимости, скачивает и сверяет пакеты, собирает обе программы статически (в госте своя libc 2.15; для `k*-selftest` — ещё тест `leap-a-day`) и initramfs, запускает прогоны по одному и пишет записи. Ничего не удаляет: скачанное и собранное лежит в `work/` и при следующем запуске берётся оттуда.

Механизм виден прямо в записи. `leapins offset` печатает настоящую разницу `CLOCK_REALTIME − CLOCK_MONOTONIC`, а `/proc/timer_list` — её копию `.offset` (часы 1, `ktime_get_real`), по которой hrtimer считает «сейчас» для таймеров по реальному времени. В `recordings/k26-load.txt`:

```
до полуночи:       CLOCK_REALTIME - CLOCK_MONOTONIC = 1341100771706269876 nsecs
                     .offset:     1341100771706316356 nsecs      (совпадают)
после секунды:     CLOCK_REALTIME - CLOCK_MONOTONIC = 1341100770706283601 nsecs
                     .offset:     1341100771706316356 nsecs      (копия на секунду впереди)
```

Ядро отвело часы на секунду назад, а копия осталась прежней: по ней сейчас на секунду больше. Ожидание «до момента T», где T меньше чем через секунду, для hrtimer уже в прошлом и заканчивается сразу, и поток с таймаутом 100 мс крутится вхолостую. `date -s` вызывает `clock_was_set()`, копия обновляется, и нагрузка пропадает. На исправленном ядре 3.2.0-29 и на современном ядре копия обновляется сама.

## Переменные окружения

| Переменная | Что задаёт | По умолчанию |
|---|---|---|
| `QEMU` | путь к `qemu-system-x86_64` | из `PATH` |
| `ACCEL` | `tcg` — программная эмуляция, `kvm` — KVM с `-cpu host` (нужен доступ к `/dev/kvm`; записи в `recordings/` сняты без KVM) | `tcg` |
| `LEAP_WORK` | каталог скачанных пакетов и сборки | `./work` |
| `MODERN_KERNEL` | ядро для прогона `modern` | `/boot/vmlinuz-$(uname -r)` |

Гостя можно запустить и вручную, без сценария, — тогда на консоли будет оболочка; выйти из QEMU — Ctrl-A, затем X:

```bash
bash scripts/run-vm.sh work/x-k26/boot/vmlinuz-3.2.0-26-generic work/initrd-base-*/initrd.gz
```

(каталог `work/initrd-base-…` появляется после первого `./run.sh`).

## Ограничения

- **Эмуляция, не железо.** Гость работает в QEMU TCG; числа пробуждений — числа эмуляции, на железе холостой цикл крутился бы быстрее.
- **Не полный дистрибутив.** В госте нет ntpd, upstart и syslog. Секунду объявляет `leapins` тем же вызовом `adjtimex`, которым это делает ntpd; путь через сам ntpd здесь не воспроизводится.
- **MySQL — версия выпуска 12.04** (5.5.22-0ubuntu1), как и остальные пакеты гостя.
- `date -s "$(date)"` в сценарии работает, потому что в госте часы и пояс — UTC.

## Первоисточники

- Исправление в основной ветке ядра: коммит 4873fa070ae8 «timekeeping: Fix leapsecond triggered load spike issue», John Stultz, 10.07.2012 — https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=4873fa070ae84a4115f0b3c9dfabc224f1bc7c51. Из сообщения коммита: «The timekeeping code misses an update of the hrtimer subsystem after a leap second happened» и «The reported immediate workaround … is causing a call to clock_was_set() which updates the hrtimer data structures».
- Ubuntu: Launchpad, ошибка 1020285 «Addition of leap second causes spuriously high CPU usage and futex lockups» — https://bugs.launchpad.net/bugs/1020285. В Ubuntu 12.04 исправление вошло в пакет linux 3.2.0-29.45 (changelog: https://changelogs.ubuntu.com/changelogs/pool/main/l/linux/linux_3.2.0-126.169/changelog), в обновления — с ядром 3.2.0-29.46, 10.08.2012.

## In English

A one-command reproduction of the Linux leap second bug of 30 June 2012. `./run.sh` downloads the Ubuntu 12.04 kernel that was in use that night (3.2.0-26.41) plus a minimal 12.04 userland, checks every file against `packages.sha256`, boots it in QEMU (software emulation, no KVM needed), sets the guest clock to 2012-06-30 23:59:35 UTC and announces a leap second with `adjtimex(ADJ_STATUS, STA_INS)`, the same call ntpd makes. After the kernel prints `Clock: inserting leap second 23:59:60 UTC`, a small program with 100 ms `pthread_cond_timedwait` timeouts jumps from 19 to tens of thousands of wakeups per second and the guest has 0 % idle until `date -s "$(date)"` is run. The fixed kernel 3.2.0-29.46 and a modern kernel show no load. Idle `rmiregistry` (OpenJDK 6) and `mysqld` 5.5 from Ubuntu 12.04 are included as separate runs.

```bash
sudo apt-get update
sudo apt-get install -y --no-install-recommends qemu-system-x86 gcc libc6-dev python3 curl ca-certificates
git clone https://github.com/works-on-my-box/leap-second-2012.git
cd leap-second-2012
./run.sh            # 3.2.0-26: leap second, load, date -s
./run.sh k29-load   # fixed kernel 3.2.0-29: no load
./run.sh all        # every run, see the table above
```

Two more pairs of runs: `k26-softirq` / `k29-softirq` add `/proc/softirqs` readings (after the leap second the `HRTIMER` counter grows by 136,579 in 5 seconds on 3.2.0-26.41 and by 1 on 3.2.0-29.46), and `k26-selftest` / `k29-selftest` run the kernel's own `leap-a-day` selftest by John Stultz, downloaded from git.kernel.org (tag v7.3) and checked against `packages.sha256`, not included in this repository (GPLv2): on 3.2.0-26.41 it reports `ERROR: hrtimer early expiration failure observed.` and exits with 1, on 3.2.0-29.46 it passes.

Recordings are in `recordings/` (`*.txt`, or `scriptreplay` with `*.typescript` and `*.timing`): made on a cloud server, except the softirq and selftest runs, which were made in a Docker container on a laptop. Upstream fix: commit 4873fa070ae8; Ubuntu bug: LP #1020285.

## Лицензия

MIT — см. `LICENSE`.
