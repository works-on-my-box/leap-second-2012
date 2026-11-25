#!/bin/bash
# run.sh [ПРОГОН...] — воспроизвести баг високосной секунды 30.06.2012 в QEMU на ядре Ubuntu 12.04 той ночи.
#   Прогоны: k26-load (по умолчанию), k29-load, k26-nofix, k26-java, k29-java, k26-mysql, k29-mysql,
#   k26-softirq, k29-softirq, k26-selftest, k29-selftest, modern, all.
#   Окружение: QEMU — путь к qemu-system-x86_64 (по умолчанию — из PATH); ACCEL=tcg|kvm (по умолчанию tcg);
#   LEAP_WORK — каталог пакетов и сборки (по умолчанию ./work);
#   MODERN_KERNEL — ядро для прогона modern (по умолчанию /boot/vmlinuz-$(uname -r)).
# Скачанное и собранное остаётся в work/ и при следующем запуске берётся оттуда;
# каждый запуск пишет записи в новый каталог out/<дата-время>. Ничего не удаляет.
set -euo pipefail
cd "$(dirname "$0")"
TOP=$PWD

# прогон → группа ядра, initramfs, сценарий гостя (demo=…), память ВМ в МБ, предел прогона в секундах
spec() {
	case "$1" in
	k26-load)  echo "k26 base auto 768 420" ;;
	k29-load)  echo "k29 base auto 768 420" ;;
	k26-nofix) echo "k26 base nofix 768 900" ;;
	k26-java)  echo "k26 java java 1024 420" ;;
	k29-java)  echo "k29 java java 1024 420" ;;
	k26-mysql) echo "k26 mysql mysql 1024 600" ;;
	k29-mysql) echo "k29 mysql mysql 1024 600" ;;
	k26-softirq)  echo "k26 base softirq 768 420" ;;
	k29-softirq)  echo "k29 base softirq 768 420" ;;
	k26-selftest) echo "k26 selftest selftest 768 300" ;;
	k29-selftest) echo "k29 selftest selftest 768 300" ;;
	modern)    echo "modern base auto 768 420" ;;
	*) return 1 ;;
	esac
}
ALL="k26-load k29-load k26-nofix k26-java k29-java k26-mysql k29-mysql k26-softirq k29-softirq k26-selftest k29-selftest modern"
RUNS="${*:-k26-load}"
[ "$RUNS" = all ] && RUNS=$ALL
for r in $RUNS; do
	spec "$r" > /dev/null || { echo "неизвестный прогон: $r (есть: $ALL, all)" >&2; exit 2; }
done

# --- зависимости ---
if [ "$(uname -m)" != x86_64 ]; then echo "нужен Linux x86-64 (здесь $(uname -m))" >&2; exit 1; fi
export QEMU="${QEMU:-qemu-system-x86_64}"
miss=()
for c in curl:curl sha256sum:coreutils timeout:coreutils dpkg-deb:dpkg gcc:gcc python3:python3 script:bsdutils "$QEMU":qemu-system-x86; do
	command -v "${c%:*}" > /dev/null 2>&1 || miss+=("${c%:*} (пакет ${c##*:})")
done
if command -v gcc > /dev/null 2>&1 && [ ! -e "$(gcc -print-file-name=libc.a)" ]; then
	miss+=("статическая libc для gcc -static (пакет libc6-dev)")
fi
if command -v script > /dev/null 2>&1 && ! script --help 2>&1 | grep -q -- --log-timing; then
	miss+=("script с ключом --log-timing (util-linux 2.35 или новее)")
fi
ti=""
for t in /usr/share/terminfo/d/dumb /lib/terminfo/d/dumb /usr/lib/terminfo/d/dumb; do
	if [ -e "$t" ]; then ti=$t; break; fi
done
[ -n "$ti" ] || miss+=("описание терминала dumb (пакет ncurses-base)")
if [ ${#miss[@]} -gt 0 ]; then
	echo "Не хватает:" >&2
	printf '  %s\n' "${miss[@]}" >&2
	echo "Ubuntu/Debian: sudo apt-get update && sudo apt-get install -y --no-install-recommends qemu-system-x86 gcc libc6-dev python3 curl ca-certificates" >&2
	exit 1
fi

# ядро хоста для прогона modern: на Ubuntu /boot/vmlinuz-* читает только root
MK="${MODERN_KERNEL:-/boot/vmlinuz-$(uname -r)}"
if [[ " $RUNS " == *" modern "* ]] && [ ! -r "$MK" ]; then
	if [ -e "$MK" ]; then
		echo "прогон modern: ядро $MK не читается." >&2
		echo "  Скопируйте его к себе (sudo cp $MK ~/vmlinuz; sudo chown $(id -un) ~/vmlinuz)" >&2
		echo "  и запустите: MODERN_KERNEL=~/vmlinuz ./run.sh modern" >&2
	else
		echo "прогон modern: ядра $MK нет; укажите файл ядра: MODERN_KERNEL=/путь/к/vmlinuz ./run.sh modern" >&2
	fi
	if [ "$*" = all ]; then
		echo "  all: modern пропущен" >&2
		RUNS=${RUNS% modern}
	else
		exit 1
	fi
fi

export LEAP_WORK="${LEAP_WORK:-$TOP/work}"
mkdir -p "$LEAP_WORK/dl" "$LEAP_WORK/bin"
W=$(cd "$LEAP_WORK" && pwd)
export LEAP_WORK=$W

# группы пакетов, нужные выбранным прогонам
groups=" base busybox "
for r in $RUNS; do
	read -r kg ig _ <<< "$(spec "$r")"
	for g in $kg $ig; do
		case "$g" in modern | base) continue ;; esac
		case "$groups" in *" $g "*) ;; *) groups="$groups$g " ;; esac
	done
done

# --- пакеты Ubuntu 12.04: скачать, сверить sha256, распаковать ---
echo "== пакеты Ubuntu 12.04:$groups"
while read -r g sum url; do
	case "$g" in '' | '#'*) continue ;; esac
	case "$groups" in *" $g "*) ;; *) continue ;; esac
	name=${url##*/}
	name=${name%%\?*}
	f="$W/dl/$name"
	if [ ! -e "$f" ]; then
		echo "   скачиваю $name"
		# недокачанное лежит в .part и докачивается (-C -); зависшая передача (меньше 1 КБ/с 30 секунд) — повтор
		n=0
		until curl -sSfL -C - --connect-timeout 30 --speed-time 30 --speed-limit 1024 -o "$f.part" "$url" ||
			echo "$sum  $f.part" | sha256sum -c --quiet - > /dev/null 2>&1; do
			n=$((n + 1))
			if [ $n -ge 5 ]; then
				echo "не скачался $url — проверьте сеть (для https нужен пакет ca-certificates)" >&2
				exit 1
			fi
			sleep 3
		done
		mv "$f.part" "$f"
	fi
	if ! echo "$sum  $f" | sha256sum -c --quiet - > /dev/null 2>&1; then
		mv "$f" "$f.bad-$(date +%s)"
		echo "sha256 не совпала: $name (файл отложен с суффиксом .bad-…); запустите run.sh ещё раз" >&2
		exit 1
	fi
done < packages.sha256
for g in $groups; do
	[ "$g" = selftest ] && continue # исходники теста ядра, не пакеты
	[ -e "$W/x-$g.done" ] && continue
	echo "   распаковываю $g"
	mkdir -p "$W/x-$g"
	while read -r gg _ url; do
		if [ "$gg" = "$g" ]; then dpkg-deb -x "$W/dl/${url##*/}" "$W/x-$g"; fi
	done < packages.sha256
	touch "$W/x-$g.done"
done
echo "   sha256 сверены, пакеты распакованы в $W"

# --- программы стенда (статически: в госте своя libc 2.15) ---
gcc -O2 -static -o "$W/bin/leapins" src/leapins.c
gcc -O2 -static -pthread -o "$W/bin/timedwait-load" src/timedwait-load.c
# тест ядра leap-a-day — только для прогонов k*-selftest; вызовы adjtimex идут прямым системным вызовом
# (src/adjtimex-syscall.c: обёртка новой glibc на ядре 3.2 не возвращает состояние часов)
case "$groups" in *" selftest "*)
	gcc -O2 -static -Wl,--wrap=adjtimex -o "$W/bin/leap-a-day" "$W/dl/leap-a-day.c" src/adjtimex-syscall.c -lrt ;;
esac

# initramfs: каталог по хешу исходников, повторный запуск берёт готовый; собирается во временный и переименовывается
initrd() {
	local key d t
	key=$( (cat src/* scripts/build-initrd.sh scripts/mkcpio.py packages.sha256; echo "$1") | sha256sum | cut -c1-12)
	d="$W/initrd-$1-$key"
	if [ ! -e "$d/initrd.gz" ]; then
		t="$d.part-$(date +%s)"
		if [ "$1" = base ]; then bash scripts/build-initrd.sh "$t" >&2; else bash scripts/build-initrd.sh "$t" "$1" >&2; fi
		mv "$t" "$d"
	fi
	echo "$d/initrd.gz"
}
kernel() {
	case "$1" in
	k26) echo "$W/x-k26/boot/vmlinuz-3.2.0-26-generic" ;;
	k29) echo "$W/x-k29/boot/vmlinuz-3.2.0-29-generic" ;;
	modern) echo "$MK" ;;
	esac
}

# --- прогоны: строго по одному (две ВМ одновременно исказили бы загрузку) ---
mkdir -p out
OUT="out/$(date +%Y%m%d-%H%M%S)"
mkdir "$OUT"
for r in $RUNS; do
	read -r kg ig demo mem lim <<< "$(spec "$r")"
	K=$(kernel "$kg")
	I=$(initrd "$ig")
	echo
	echo "== $r: ядро $(basename "$K"), demo=$demo, память $mem МБ; начало $(date '+%H:%M:%S')"
	cmd=$(printf '%q ' bash scripts/run-vm.sh "$K" "$I" "demo=$demo")
	# консоль ВМ пишет script: текст и файл времени для scriptreplay
	VM_MEM=$mem timeout "$lim" script -q -f -e --log-timing "$OUT/$r.timing" -O "$OUT/$r.raw" -c "$cmd" < /dev/null &
	vm=$!
	stop=""
	trap 'stop=1; kill -TERM $vm 2> /dev/null' INT TERM
	st=0
	wait $vm || st=$?
	if [ -n "$stop" ]; then
		wait $vm 2> /dev/null || true
		echo "прервано: $r" >&2
		exit 130
	fi
	trap - INT TERM
	[ $st -eq 0 ] || echo "   код выхода $st (124 — сработал предел $lim с)"
	python3 -I scripts/clean-typescript.py "$OUT/$r.raw" "$OUT/$r.txt" "$OUT/$r.typescript" > /dev/null
	echo "== $r: конец $(date '+%H:%M:%S'); запись — $OUT/$r.txt"
	grep -h "inserting leap second" "$OUT/$r.txt" || echo "   в записи нет строки ядра о вставке секунды"
done
echo
echo "Записи: $OUT/ (*.txt — текст; *.typescript и *.timing — для scriptreplay)."
echo "Воспроизвести: scriptreplay --log-timing $OUT/${r}.timing --log-out $OUT/${r}.typescript"
