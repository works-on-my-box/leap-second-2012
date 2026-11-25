#!/bin/bash
# Сценарий стенда с Java из Ubuntu 12.04: простаивающий rmiregistry (OpenJDK 6) переживает вставку
# високосной секунды 30.06.2012 23:59:60 UTC, затем обход date -s "$(date)".
# Команды печатаются с приглашением, как в терминале; [java] — загрузка процессора процессом java раз в секунду
# (тики utime+stime из /proc/PID/stat; CLK_TCK=100, поэтому тики за секунду = проценты одного процессора).
export PATH=/usr/lib/jvm/java-6-openjdk-amd64/jre/bin:$PATH
p() { echo; echo "root@probe:~# $*"; }
run() { p "$*"; bash -c "$*"; }
# offs: настоящая разница REALTIME-MONOTONIC и её копии в hrtimer (по одной на процессор) — должны совпадать
offs() { run "leapins offset; grep -A5 'clock 1:' /proc/timer_list | grep offset"; }
ticks() { awk '{print $14+$15}' /proc/$JPID/stat; }
watch_java() {
	i=0; prev=$(ticks)
	while [ $i -lt $1 ]; do
		sleep 1; cur=$(ticks)
		echo "[java] $(date -u +%T) UTC  pid=$JPID  cpu=$((cur - prev))%"
		prev=$cur; i=$((i+1))
	done
}
snap() {
	echo; echo "---------- $1 ----------"
	run "top -b -n 2 -d 1 -p $JPID | awk '/^top -/{n++} n==2' | tail -n 2"
	run "top -b -H -n 2 -d 1 -p $JPID | awk '/^top -/{n++} n==2' | sed -n '7,13p'"
	run 'mpstat -P ALL 1 1 | head -n 6'
}

run 'uname -a'
run 'java -version'
# часы ставим ДО запуска JVM, чтобы шаг часов назад, в 2012 год, не пришёлся на работающий процесс
run 'date -u -s "2012-06-30 23:59:00"'
run 'leapins'
p 'rmiregistry &'
rmiregistry > /tmp/rmi.log 2>&1 &
JPID=$!
run 'sleep 20; ps -o pid,nlwp,stat,args -p '"$JPID"
watch_java 8
snap "ДО полуночи"
run 'leapins show; date -u'
offs
watch_java 32
run 'dmesg | grep -i -E "leap|clock:"'
run 'leapins show; date -u'
offs
snap "ПОСЛЕ вставленной секунды"
watch_java 5
run 'date -s "$(date)"'
watch_java 6
snap "ПОСЛЕ date -s"
run 'leapins show; date -u'
offs
kill $JPID
