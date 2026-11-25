#!/bin/bash
# Сценарий стенда с MySQL 5.5 из Ubuntu 12.04: простаивающий mysqld (без единого запроса) переживает вставку
# високосной секунды 30.06.2012 23:59:60 UTC, затем обход date -s "$(date)".
# Команды печатаются с приглашением, как в терминале; [mysqld] — загрузка процессора процессом mysqld раз в секунду
# (тики utime+stime из /proc/PID/stat; CLK_TCK=100, поэтому тики за секунду = проценты одного процессора).
p() { echo; echo "root@probe:~# $*"; }
run() { p "$*"; bash -c "$*"; }
# offs: настоящая разница REALTIME-MONOTONIC и её копии в hrtimer (по одной на процессор) — должны совпадать
offs() { run "leapins offset; grep -A5 'clock 1:' /proc/timer_list | grep offset"; }
ticks() { awk '{print $14+$15}' /proc/$MPID/stat; }
line() { echo "[mysqld] $(date -u +%T) UTC  pid=$MPID  cpu=$(($2 - $1))%"; }
watch_mysqld() {
	i=0; prev=$(ticks)
	while [ $i -lt $1 ]; do sleep 1; cur=$(ticks); line $prev $cur; prev=$cur; i=$((i+1)); done
}
# построчно до полуночи по часам гостя (сколько бы ни запускался mysqld), затем ещё N секунд
watch_to_midnight() {
	prev=$(ticks)
	while [ "$(date -u +%H)" = 23 ]; do sleep 1; cur=$(ticks); line $prev $cur; prev=$cur; done
	watch_mysqld $1
}
snap() {
	echo; echo "---------- $1 ----------"
	run "top -b -n 2 -d 1 -p $MPID | awk '/^top -/{n++} n==2' | tail -n 2"
	run "top -b -H -n 2 -d 1 -p $MPID | awk '/^top -/{n++} n==2' | sed -n '7,16p'"
	run 'mpstat -P ALL 1 1 | head -n 6'
}

run 'uname -a'
run 'mysqld --version'
# каталог данных создаётся здесь же, в госте (tmpfs), штатным mysql_install_db из пакета 12.04
run 'mysql_install_db --no-defaults --force --user=root --basedir=/usr --datadir=/tmp/mysql > /tmp/install.log 2>&1; echo "exit=$?"; grep -i -E "ok|error" /tmp/install.log | head -n 5; ls /tmp/mysql'
# часы ставим ДО запуска mysqld, чтобы шаг часов назад, в 2012 год, не пришёлся на работающий процесс
run 'date -u -s "2012-06-30 23:58:50"'
run 'leapins'
p 'mysqld --no-defaults --user=root --datadir=/tmp/mysql --socket=/tmp/mysql.sock --pid-file=/tmp/mysql.pid --skip-networking --log-error=/tmp/mysql.err &'
mysqld --no-defaults --user=root --datadir=/tmp/mysql --socket=/tmp/mysql.sock --pid-file=/tmp/mysql.pid \
	--skip-networking --log-error=/tmp/mysql.err > /dev/null 2>&1 &
MPID=$!
run 'i=0; until [ -S /tmp/mysql.sock ] || [ $i -ge 120 ]; do sleep 1; i=$((i+1)); done; tail -n 2 /tmp/mysql.err; ps -o pid,nlwp,stat,args -p '"$MPID"
watch_mysqld 5
snap "ДО полуночи"
run 'leapins show; date -u'
offs
watch_to_midnight 5
run 'dmesg | grep -i -E "leap|clock:"'
run 'leapins show; date -u'
offs
snap "ПОСЛЕ вставленной секунды"
watch_mysqld 5
run 'date -s "$(date)"'
watch_mysqld 6
snap "ПОСЛЕ date -s"
run 'leapins show; date -u'
offs
kill $MPID
