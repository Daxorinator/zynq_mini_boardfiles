/* Linux-side memory stability test: two threads (one per core) each fill a private region with a pseudo-random pattern,
 * its inverse, and address-derived words, then verify, for several passes. Both cores hammering the DDR at once is the point.
 * usage: memtest [MiB per thread (default 128)] [passes (default 3)]       Prints "MEMTEST RESULT: PASS" or "FAIL".
 * Keep MiB*2 below the free memory of the board (the PYNQ image leaves about 370 MB free). */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>

static size_t words; static int passes; static uint64_t errors[2];
static uint64_t xs(uint64_t *s) { uint64_t x = *s; x ^= x << 13; x ^= x >> 7; x ^= x << 17; return *s = x; }
static void *worker(void *arg)
{
	int id = (int)(intptr_t)arg;
	uint64_t *m = mmap(NULL, words * 8, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_POPULATE, -1, 0);
	if (m == MAP_FAILED) { perror("mmap"); errors[id] = ~0ull; return NULL; }
	for (int p = 0; p < passes; p++) {
		for (int kind = 0; kind < 4; kind++) {
			uint64_t s = 0x9E3779B97F4A7C15ull * (id + 1) + p * 7919 + kind, v;
			for (size_t i = 0; i < words; i++) {
				v = kind == 0 ? xs(&s) : kind == 1 ? ~xs(&s) : kind == 2 ? (uint64_t)(uintptr_t)&m[i] * 0x100000001ull : (i & 1 ? 0xAAAAAAAAAAAAAAAAull : 0x5555555555555555ull);
				m[i] = v;
			}
			s = 0x9E3779B97F4A7C15ull * (id + 1) + p * 7919 + kind;
			for (size_t i = 0; i < words; i++) {
				v = kind == 0 ? xs(&s) : kind == 1 ? ~xs(&s) : kind == 2 ? (uint64_t)(uintptr_t)&m[i] * 0x100000001ull : (i & 1 ? 0xAAAAAAAAAAAAAAAAull : 0x5555555555555555ull);
				if (m[i] != v) { if (errors[id] < 5) fprintf(stderr, "thread %d pass %d kind %d word %zu: %016llx != %016llx\n", id, p, kind, i, (unsigned long long)m[i], (unsigned long long)v); errors[id]++; }
			}
		}
	}
	munmap(m, words * 8);
	return NULL;
}
int main(int argc, char **argv)
{
	size_t mib = argc > 1 ? strtoul(argv[1], 0, 0) : 128; passes = argc > 2 ? atoi(argv[2]) : 3;
	words = mib * 1024 * 1024 / 8;
	pthread_t t[2];
	for (int i = 0; i < 2; i++) pthread_create(&t[i], NULL, worker, (void *)(intptr_t)i);
	for (int i = 0; i < 2; i++) pthread_join(t[i], NULL);
	uint64_t e = errors[0] + errors[1];
	printf("tested 2 x %zu MiB, %d passes x 4 patterns, errors: %llu\n", mib, passes, (unsigned long long)e);
	printf("MEMTEST RESULT: %s\n", e ? "FAIL" : "PASS");
	return e ? 1 : 0;
}
