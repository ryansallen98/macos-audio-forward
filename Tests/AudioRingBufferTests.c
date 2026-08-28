#include "AudioForwardBuffer.h"

#include <assert.h>
#include <math.h>
#include <stdio.h>

static void require_sample(float actual, float expected) {
  assert(fabsf(actual - expected) < 0.0001f);
}

static void test_priming_and_underrun_recovery(void) {
  AFAudioRingBuffer *buffer = AFAudioRingBufferCreate(16, 4, 0);
  assert(buffer != NULL);

  const float first[] = {1, 10, 2, 20, 3, 30};
  assert(AFAudioRingBufferWriteStereoInterleaved(buffer, first, 3) == 3);

  float left[4] = {-1, -1, -1, -1};
  float right[4] = {-1, -1, -1, -1};
  assert(AFAudioRingBufferReadStereoPlanar(buffer, left, right, 2) == 0);
  require_sample(left[0], 0);
  require_sample(right[0], 0);

  const float second[] = {4, 40, 5, 50, 6, 60};
  assert(AFAudioRingBufferWriteStereoInterleaved(buffer, second, 3) == 3);
  assert(AFAudioRingBufferReadStereoPlanar(buffer, left, right, 4) == 4);
  for (int frame = 0; frame < 4; frame++) {
    require_sample(left[frame], (float)(frame + 1));
    require_sample(right[frame], (float)((frame + 1) * 10));
  }

  assert(AFAudioRingBufferReadStereoPlanar(buffer, left, right, 4) == 2);
  require_sample(left[0], 5);
  require_sample(left[1], 6);
  require_sample(left[3], 0);
  AFAudioRingBufferStats stats = AFAudioRingBufferGetStats(buffer);
  assert(stats.underrun_events == 1);
  assert(stats.underrun_frames == 2);
  assert(!stats.primed);

  const float recovery[] = {7, 70, 8, 80, 9, 90, 10, 100};
  assert(AFAudioRingBufferWriteStereoInterleaved(buffer, recovery, 4) == 4);
  assert(AFAudioRingBufferReadStereoPlanar(buffer, left, right, 4) == 4);
  require_sample(left[0], 7);
  require_sample(left[3], 10);
  AFAudioRingBufferDestroy(buffer);
}

static void test_overflow_is_bounded(void) {
  AFAudioRingBuffer *buffer = AFAudioRingBufferCreate(4, 1, 0);
  assert(buffer != NULL);
  const float samples[] = {
    1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  };
  assert(AFAudioRingBufferWriteStereoInterleaved(buffer, samples, 6) == 4);
  const AFAudioRingBufferStats stats = AFAudioRingBufferGetStats(buffer);
  assert(stats.available_frames == 4);
  assert(stats.overflow_events == 1);
  assert(stats.overflow_frames == 2);
  AFAudioRingBufferDestroy(buffer);
}

static void test_controlled_latency_trim(void) {
  AFAudioRingBuffer *buffer = AFAudioRingBufferCreate(16, 1, 0);
  assert(buffer != NULL);
  const float samples[] = {
    1, 10, 2, 20, 3, 30, 4, 40, 5, 50, 6, 60, 7, 70, 8, 80,
  };
  assert(AFAudioRingBufferWriteStereoInterleaved(buffer, samples, 8) == 8);
  AFAudioRingBufferRequestTrim(buffer, 3);

  float left[2] = {0};
  float right[2] = {0};
  assert(AFAudioRingBufferReadStereoPlanar(buffer, left, right, 2) == 2);
  require_sample(left[0], 6);
  require_sample(left[1], 7);
  const AFAudioRingBufferStats stats = AFAudioRingBufferGetStats(buffer);
  assert(stats.trimmed_frames == 5);
  assert(stats.available_frames == 1);
  AFAudioRingBufferDestroy(buffer);
}

int main(void) {
  test_priming_and_underrun_recovery();
  test_overflow_is_bounded();
  test_controlled_latency_trim();
  puts("Audio ring buffer tests passed.");
  return 0;
}
