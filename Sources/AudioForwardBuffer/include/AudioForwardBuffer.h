#ifndef AUDIO_FORWARD_BUFFER_H
#define AUDIO_FORWARD_BUFFER_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct AFAudioRingBuffer AFAudioRingBuffer;

typedef struct {
  uint32_t capacity_frames;
  uint32_t available_frames;
  uint32_t startup_frames;
  uint64_t total_written_frames;
  uint64_t total_read_frames;
  uint64_t underrun_events;
  uint64_t underrun_frames;
  uint64_t overflow_events;
  uint64_t overflow_frames;
  uint64_t trimmed_frames;
  bool primed;
} AFAudioRingBufferStats;

AFAudioRingBuffer *AFAudioRingBufferCreate(
  uint32_t capacity_frames,
  uint32_t startup_frames,
  uint32_t fade_frames
);

void AFAudioRingBufferDestroy(AFAudioRingBuffer *buffer);
void AFAudioRingBufferReset(AFAudioRingBuffer *buffer);
void AFAudioRingBufferSetStartupFrames(AFAudioRingBuffer *buffer, uint32_t startup_frames);

uint32_t AFAudioRingBufferWriteStereoInterleaved(
  AFAudioRingBuffer *buffer,
  const float *samples,
  uint32_t frames
);

uint32_t AFAudioRingBufferReadStereoPlanar(
  AFAudioRingBuffer *buffer,
  float *left,
  float *right,
  uint32_t frames
);

void AFAudioRingBufferRequestTrim(AFAudioRingBuffer *buffer, uint32_t frames_to_keep);
AFAudioRingBufferStats AFAudioRingBufferGetStats(const AFAudioRingBuffer *buffer);

#ifdef __cplusplus
}
#endif

#endif
