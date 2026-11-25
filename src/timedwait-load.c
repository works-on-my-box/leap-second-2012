/* timedwait-load: N потоков, каждый в цикле ждёт условную переменную (pthread_cond_timedwait)
 * с таймаутом 100 мс; таймаут — абсолютное время, и по умолчанию условная переменная
 * меряет его по CLOCK_REALTIME.
 * В норме поток просыпается 10 раз в секунду и процессор почти не тратит.
 * Раз в секунду печатает: время UTC, число пробуждений за секунду, загрузку процессора процессом.
 *   timedwait-load [потоков=2] [секунд=0 — бесконечно]
 */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

#define MAXT 64
static volatile unsigned long wakeups[MAXT];

static void *worker(void *arg)
{
	long i = (long)arg;
	pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
	pthread_cond_t c = PTHREAD_COND_INITIALIZER;	/* часы условной переменной — CLOCK_REALTIME */
	pthread_mutex_lock(&m);
	for (;;) {
		struct timespec ts;
		clock_gettime(CLOCK_REALTIME, &ts);
		ts.tv_nsec += 100 * 1000 * 1000;	/* +100 мс */
		if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
		pthread_cond_timedwait(&c, &m, &ts);	/* никто не сигналит: ждём таймаута */
		wakeups[i]++;
	}
	return NULL;
}

static double now(clockid_t id)
{
	struct timespec ts;
	clock_gettime(id, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 2;
	int secs = argc > 2 ? atoi(argv[2]) : 0;
	if (n < 1 || n > MAXT) n = 2;
	setvbuf(stdout, NULL, _IOLBF, 0);

	pthread_t th[MAXT];
	for (long i = 0; i < n; i++)
		pthread_create(&th[i], NULL, worker, (void *)i);

	unsigned long prev = 0;
	double pm = now(CLOCK_MONOTONIC), pc = now(CLOCK_PROCESS_CPUTIME_ID);
	for (int k = 0; secs == 0 || k < secs; k++) {
		sleep(1);	/* относительный сон: ядро ведёт его по монотонным часам — баг его не задевает */
		unsigned long sum = 0;
		for (int i = 0; i < n; i++) sum += wakeups[i];
		double m = now(CLOCK_MONOTONIC), c = now(CLOCK_PROCESS_CPUTIME_ID);
		time_t t = time(NULL);
		struct tm tm;
		gmtime_r(&t, &tm);
		printf("[load] %02d:%02d:%02d UTC  threads=%d  wakeups/s=%-9lu cpu=%5.1f%%\n",
		       tm.tm_hour, tm.tm_min, tm.tm_sec, n,
		       (unsigned long)((sum - prev) / (m - pm)), 100.0 * (c - pc) / (m - pm));
		prev = sum; pm = m; pc = c;
	}
	return 0;
}
