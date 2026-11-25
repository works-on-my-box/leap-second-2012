/* leapins: объявить ядру вставку високосной секунды в ближайшую полночь UTC
 * (то же, что делал ntpd, получив от сервера бит «в конце суток вставить секунду»), или показать состояние.
 *   leapins        — выставить STA_INS (и малую ошибку часов, чтобы ядро не сочло часы несинхронизированными)
 *   leapins show   — только показать состояние
 * Вызов — прямой системный adjtimex: обёртка новой glibc идёт через clock_adjtime, а в ядрах 3.2
 * clock_adjtime не возвращает структуру, если результат не 0 (TIME_INS и т. п.).
 */
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/timex.h>
#include <time.h>
#include <unistd.h>

static const char *state_name(int s)
{
	switch (s) {
	case TIME_OK:    return "TIME_OK";
	case TIME_INS:   return "TIME_INS (insert leap second at midnight UTC)";
	case TIME_DEL:   return "TIME_DEL";
	case TIME_OOP:   return "TIME_OOP (leap second in progress)";
	case TIME_WAIT:  return "TIME_WAIT (leap second has occurred)";
	case TIME_ERROR: return "TIME_ERROR (clock unsynchronized)";
	default:         return "?";
	}
}

static long kadjtimex(struct timex *t)
{
	return syscall(SYS_adjtimex, t);
}

static int show(const char *label)
{
	struct timex t;
	memset(&t, 0, sizeof t);
	long r = kadjtimex(&t);
	if (r < 0) { perror("adjtimex"); return -1; }
	printf("%s: adjtimex()=%ld %s, status=0x%04x%s%s\n", label, r, state_name((int)r),
	       t.status, (t.status & STA_INS) ? " STA_INS" : "",
	       (t.status & STA_UNSYNC) ? " STA_UNSYNC" : "");
	return (int)r;
}

/* Настоящая разница CLOCK_REALTIME - CLOCK_MONOTONIC: её надо сравнивать с .offset часов 1
 * (ktime_get_real) в /proc/timer_list — это копия, по которой hrtimer считает «настоящее время». */
static void offset(void)
{
	struct timespec a, m, b;
	clock_gettime(CLOCK_REALTIME, &a);
	clock_gettime(CLOCK_MONOTONIC, &m);
	clock_gettime(CLOCK_REALTIME, &b);
	long long real = ((long long)a.tv_sec * 1000000000LL + a.tv_nsec +
			  (long long)b.tv_sec * 1000000000LL + b.tv_nsec) / 2;
	long long mono = (long long)m.tv_sec * 1000000000LL + m.tv_nsec;
	printf("CLOCK_REALTIME - CLOCK_MONOTONIC = %lld nsecs\n", real - mono);
}

int main(int argc, char **argv)
{
	if (argc > 1 && strcmp(argv[1], "show") == 0)
		return show("state") < 0;
	if (argc > 1 && strcmp(argv[1], "offset") == 0) {
		offset();
		return 0;
	}

	show("before");
	struct timex t;
	memset(&t, 0, sizeof t);
	t.modes = ADJ_STATUS | ADJ_MAXERROR | ADJ_ESTERROR;
	t.status = STA_INS;		/* часы синхронизированы, объявлена вставка секунды */
	t.maxerror = 100000;		/* 100 мс, в микросекундах */
	t.esterror = 1000;
	if (kadjtimex(&t) < 0) { perror("adjtimex(ADJ_STATUS)"); return 1; }
	return show("after ") < 0;
}
