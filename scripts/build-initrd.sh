#!/bin/bash
# build-initrd.sh OUT [java|mysql|selftest] — собрать initramfs гостя в НОВЫЙ каталог OUT (существующий не трогает): OUT/initrd.gz.
# Состав: пакеты Ubuntu 12.04 (libc6 2.15, coreutils 8.13, procps 3.2.8, sysstat 10.0.3, ncurses 5.9),
# busybox-static 1.18.5 из 12.04, программы стенда leapins и timedwait-load, /init и сценарии /demo*.sh;
# с java — ещё OpenJDK 6 из 12.04, с mysql — ещё MySQL 5.5 из 12.04, с selftest — ещё тест ядра leap-a-day.
# Распакованные пакеты (x-base, x-busybox, x-java, x-mysql) и собранные программы (bin) берутся из LEAP_WORK —
# их готовит run.sh.
set -euo pipefail
TOP="$(cd "$(dirname "$0")/.." && pwd)"
B="${LEAP_WORK:-$TOP/work}"
OUT="$1"
if [ -e "$OUT" ]; then echo "уже есть: $OUT" >&2; exit 1; fi
mkdir -p "$OUT/root"
R="$OUT/root"
cp -a "$B/x-base/." "$R/"
cp -a "$B/x-busybox/bin/busybox" "$R/bin/busybox"
for a in $("$B/x-busybox/bin/busybox" --list); do
	if [ ! -e "$R/bin/$a" ] && [ ! -e "$R/usr/bin/$a" ] && [ ! -e "$R/sbin/$a" ] && [ ! -e "$R/usr/sbin/$a" ]; then
		ln -s busybox "$R/bin/$a"
	fi
done
mkdir -p "$R/usr/share/terminfo/d" "$R/usr/local/bin" "$R/proc" "$R/sys" "$R/tmp" "$R/root"
# описание терминала dumb — из системы (в разных выпусках лежит в разных местах)
for t in /usr/share/terminfo/d/dumb /lib/terminfo/d/dumb /usr/lib/terminfo/d/dumb; do
	if [ -e "$t" ]; then cp "$t" "$R/usr/share/terminfo/d/dumb"; break; fi
done
cp "$B/bin/leapins" "$B/bin/timedwait-load" "$R/usr/local/bin/"
cp "$TOP/src/init" "$R/init"
for s in demo.sh demo-java.sh demo-nofix.sh demo-mysql.sh demo-softirq.sh demo-selftest.sh; do
	cp "$TOP/src/$s" "$R/$s"
	chmod 755 "$R/$s"
done
chmod 755 "$R/init"
sed -i 's#^export PATH=.*#export PATH=/usr/local/bin:/bin:/sbin:/usr/bin:/usr/sbin TERM=dumb HOME=/root#' "$R/init"
G="base|busybox"
case "${2:-}" in
java)
	# OpenJDK 6 из Ubuntu 12.04 (и libstdc++6, libgcc1, zlib1g, tzdata-java)
	cp -a "$B/x-java/." "$R/"
	G="$G|java"
	;;
mysql)
	# MySQL 5.5 из Ubuntu 12.04 (mysql-server-core-5.5 и его библиотеки)
	cp -a "$B/x-mysql/." "$R/"
	# mysql_install_db и mysqld --user=root ищут пользователя root в /etc/passwd
	mkdir -p "$R/etc"
	echo "root:x:0:0:root:/root:/bin/bash" > "$R/etc/passwd"
	echo "root:x:0:" > "$R/etc/group"
	G="$G|mysql"
	;;
selftest)
	# тест ядра leap-a-day, который run.sh собирает статически (исходник скачан по packages.sha256)
	cp "$B/bin/leap-a-day" "$R/usr/local/bin/"
	;;
esac
# список пакетов гостя (его печатает сценарий: cat /PACKAGES.txt)
awk -v g="^($G)\$" '$1 ~ g { n = split($3, p, "/"); print p[n] }' "$TOP/packages.sha256" | LC_ALL=C sort -u > "$R/PACKAGES.txt"
python3 -I "$TOP/scripts/mkcpio.py" "$R" "$OUT/initrd.gz"
ls -la "$OUT/initrd.gz"
