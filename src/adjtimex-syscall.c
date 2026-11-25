/* adjtimex-syscall.c: adjtimex() прямым системным вызовом — для теста ядра leap-a-day,
 * который run.sh собирает статически с новой glibc (ключ компоновщика -Wl,--wrap=adjtimex
 * направляет сюда все вызовы adjtimex из теста; исходник теста не меняется).
 * Обёртка adjtimex в новой glibc вызывает clock_adjtime(CLOCK_REALTIME, …), а в ядрах 3.2
 * clock_adjtime не возвращает структуру, если результат не 0 (TIME_INS, TIME_OOP, TIME_WAIT), —
 * тест не увидел бы ни времени, ни флагов. В glibc 2.15 из Ubuntu 12.04 adjtimex — прямой вызов,
 * как здесь (то же в leapins.c).
 */
#include <sys/syscall.h>
#include <sys/timex.h>
#include <unistd.h>

int __wrap_adjtimex(struct timex *t)
{
	return syscall(SYS_adjtimex, t);
}
