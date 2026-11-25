#!/bin/bash
# run-vm.sh KERNEL INITRD [доп. параметры ядра] — запуск гостя в QEMU, консоль — последовательный порт в этом терминале.
# QEMU — переменной QEMU=/путь/к/qemu-system-x86_64; без неё — qemu-system-x86_64 из PATH.
# Ускоритель — ACCEL=tcg (по умолчанию: программная эмуляция, -cpu qemu64) или ACCEL=kvm (-cpu host).
# Память гостя — VM_MEM в МБ (по умолчанию 768). Без demo=… в параметрах гость даёт оболочку;
# выйти из QEMU — Ctrl-A, затем X.
set -euo pipefail
K="$1"; I="$2"; shift 2
case "${ACCEL:-tcg}" in
kvm) AARGS=(-accel kvm -cpu host) ;;
*) AARGS=(-accel tcg,thread=multi -cpu qemu64) ;;
esac
exec "${QEMU:-qemu-system-x86_64}" \
	-machine pc "${AARGS[@]}" -smp 2 -m "${VM_MEM:-768}" \
	-nographic -no-reboot -net none \
	-kernel "$K" -initrd "$I" -append "console=ttyS0 quiet $*"
