#!/bin/bash
# Сценарий стенда «само не пройдёт»: вставка високосной секунды 30.06.2012 23:59:60 UTC, затем ПЯТЬ МИНУТ без обхода
# (строка нагрузки раз в 10 секунд, снимок top на 1-й, 3-й и 5-й минуте), и только потом date -s "$(date)".
# Команды печатаются с приглашением, как в терминале; [load] — строки программы нагрузки.
p() { echo; echo "root@probe:~# $*"; }
run() { p "$*"; bash -c "$*"; }
watch_load() { i=0; while [ $i -lt $1 ]; do sleep 1; tail -n 1 /tmp/load.log; i=$((i+1)); done; }
# offs: настоящая разница REALTIME-MONOTONIC и её копии в hrtimer (по одной на процессор) — должны совпадать
offs() { run "leapins offset; grep -A5 'clock 1:' /proc/timer_list | grep offset"; }
topsnap() { run "top -b -n 2 -d 1 | awk '/^top -/{n++} n==2' | head -n 11"; run 'cat /proc/loadavg'; }
snap() {
	echo; echo "---------- $1 ----------"
	topsnap
	run 'mpstat -P ALL 1 1 | head -n 6'
}

run "cat /PACKAGES.txt"
run "uname -a"
run 'date --version | head -n 1'
run 'date -u -s "2012-06-30 23:59:35"'
run 'leapins'
p 'timedwait-load 2 > /tmp/load.log &'
timedwait-load 2 > /tmp/load.log 2>&1 &
LOAD=$!
watch_load 7
snap "ДО полуночи"
run 'leapins show; date -u'
watch_load 22
run 'dmesg | grep -i -E "leap|clock:"'
run 'leapins show; date -u'
offs
echo; echo "---------- ПЯТЬ МИНУТ без обхода: строка нагрузки раз в 10 секунд ----------"
echo "# 30 раз по 10 секунд: последняя строка нагрузки; на 1-й, 3-й и 5-й минуте — снимок top и /proc/loadavg"
i=1
while [ $i -le 30 ]; do
	sleep 10
	tail -n 1 /tmp/load.log
	case $i in
	6) echo; echo "---------- 1-я минута после секунды ----------"; topsnap ;;
	18) echo; echo "---------- 3-я минута после секунды ----------"; topsnap ;;
	30) echo; echo "---------- 5-я минута после секунды ----------"; topsnap ;;
	esac
	i=$((i+1))
done
snap "ПОСЛЕ пяти минут без обхода"
run 'leapins show; date -u'
offs
run 'date -s "$(date)"'
watch_load 6
snap "ПОСЛЕ date -s"
run 'leapins show; date -u'
offs
kill $LOAD
