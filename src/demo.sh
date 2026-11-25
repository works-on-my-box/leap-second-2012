#!/bin/bash
# Сценарий стенда: вставка високосной секунды 30.06.2012 23:59:60 UTC и обход date -s "$(date)".
# Команды печатаются с приглашением, как в терминале; [load] — строки программы нагрузки раз в секунду.
p() { echo; echo "root@probe:~# $*"; }
run() { p "$*"; bash -c "$*"; }
watch_load() { i=0; while [ $i -lt $1 ]; do sleep 1; tail -n 1 /tmp/load.log; i=$((i+1)); done; }
# offs: настоящая разница REALTIME-MONOTONIC и её копии в hrtimer (по одной на процессор) — должны совпадать
offs() { run "leapins offset; grep -A5 'clock 1:' /proc/timer_list | grep offset"; }
snap() {
	echo; echo "---------- $1 ----------"
	run "top -b -n 2 -d 1 | awk '/^top -/{n++} n==2' | head -n 11"
	run 'mpstat -P ALL 1 1 | head -n 6'
	run 'cat /proc/loadavg'
}

run "cat /PACKAGES.txt"
run "uname -a"
run 'cat /proc/version'
run 'cat /sys/devices/system/clocksource/clocksource0/current_clocksource; grep -m1 hres_active /proc/timer_list'
run 'date --version | head -n 1'
run 'date -u -s "2012-06-30 23:59:35"'
run 'leapins'
p 'timedwait-load 2 > /tmp/load.log &'
timedwait-load 2 > /tmp/load.log 2>&1 &
LOAD=$!
watch_load 7
snap "ДО полуночи"
run 'leapins show; date -u'
offs
watch_load 22
run 'dmesg | grep -i -E "leap|clock:"'
run 'leapins show; date -u'
offs
snap "ПОСЛЕ вставленной секунды"
watch_load 5
run 'date -s "$(date)"'
watch_load 6
snap "ПОСЛЕ date -s"
run 'leapins show; date -u'
offs
kill $LOAD
