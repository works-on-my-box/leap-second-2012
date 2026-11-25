#!/bin/bash
# Сценарий стенда: тест ядра leap-a-day (tools/testing/selftests/timers в дереве Linux, автор — John Stultz)
# на одну вставку секунды. Часы гостя — 30.06.2012 23:59:35 UTC, как в demo.sh; тест сам ставит их
# за 10 секунд до ближайшей полуночи UTC, объявляет секунду, печатает состояние ядра раз в полсекунды,
# а после секунды проверяет, не сработал ли таймер раньше срока («hrtimer early expiration»).
# Команды печатаются с приглашением, как в терминале.
p() { echo; echo "root@probe:~# $*"; }
run() { p "$*"; bash -c "$*"; }
# offs: настоящая разница REALTIME-MONOTONIC и её копии в hrtimer (по одной на процессор) — должны совпадать
offs() { run "leapins offset; grep -A5 'clock 1:' /proc/timer_list | grep offset"; }

run "cat /PACKAGES.txt"
run "uname -a"
run 'cat /proc/version'
run 'cat /sys/devices/system/clocksource/clocksource0/current_clocksource; grep -m1 hres_active /proc/timer_list'
run 'date -u -s "2012-06-30 23:59:35"'
run 'leap-a-day -i 1; echo "код выхода: $?"'
run 'dmesg | grep -i -E "leap|clock:"'
run 'leapins show; date -u'
offs
