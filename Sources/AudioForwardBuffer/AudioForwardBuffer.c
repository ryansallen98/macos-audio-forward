#include "AudioForwardBuffer.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define AF_NO_TRIM_REQUEST UINT32_MAX

struct AFAudioRingBuffer {
  float *samples;
  uint32_t capacity_frames;
  uint32_t fade_frames;

  _Atomic uint64_t read_cursor;
  _Atomic uint64_t write_cursor;
  _Atomic uint32_t startup_frames;
  _Atomic uint32_t trim_target_frames;
  _Atomic bool primed;

  _Atomic uint64_t total_written_frames;
  _Atomic uint64_t total_read_frames;
  _Atomic uint64_t underrun_events;
  _Atomic uint64_t underrun_frames;
  _Atomic uint64_t overflow_events;
  _Atomic uint64_t overflow_frames;
  _Atomic uint64_t trimmed_frames;

  uint32_t fade_remaining;
  float last_left;
  float last_right;
};

static uint32_t af_clamp_startup(const AFAudioRingBuffer *buffer, uint32_t frames) {
  if (frames < 1) {
    return 1;
  }
  if (frames > buffer->capacity_frames) {
    return buffer->capacity_frames;
  }
  return frames;
}

static void af_zero(float *left, float *right, uint32_t start, uint32_t frames) {
  if (frames == 0) {
    return;
  }
  memset(left + start, 0, (size_t)frames * sizeof(float));
  memset(right + start, 0, (size_t)frames * sizeof(float));
}

AFAudioRingBuffer *AFAudioRingBufferCreate(
  uint32_t capacity_frames,
  uint32_t startup_frames,
  uint32_t fade_frames
) {
  if (capacity_frames < 2) {
    return NULL;
  }

  AFAudioRingBuffer *buffer = calloc(1, sizeof(AFAudioRingBuffer));
  if (buffer == NULL) {
    return NULL;
  }
  buffer->samples = calloc((size_t)capacity_frames * 2, sizeof(float));
  if (buffer->samples == NULL) {
    free(buffer);
    return NULL;
  }

  buffer->capacity_frames = capacity_frames;
  buffer->fade_frames = fade_frames;
  atomic_init(&buffer->read_cursor, 0);
  atomic_init(&buffer->write_cursor, 0);
  atomic_init(&buffer->startup_frames, af_clamp_startup(buffer, startup_frames));
  atomic_init(&buffer->trim_target_frames, AF_NO_TRIM_REQUEST);
  atomic_init(&buffer->primed, false);
  atomic_init(&buffer->total_written_frames, 0);
  atomic_init(&buffer->total_read_frames, 0);
  atomic_init(&buffer->underrun_events, 0);
  atomic_init(&buffer->underrun_frames, 0);
  atomic_init(&buffer->overflow_events, 0);
  atomic_init(&buffer->overflow_frames, 0);
  atomic_init(&buffer->trimmed_frames, 0);
  return buffer;
}

void AFAudioRingBufferDestroy(AFAudioRingBuffer *buffer) {
  if (buffer == NULL) {
    return;
  }
  free(buffer->samples);
  free(buffer);
}

void AFAudioRingBufferReset(AFAudioRingBuffer *buffer) {
  if (buffer == NULL) {
    return;
  }
  atomic_store_explicit(&buffer->read_cursor, 0, memory_order_release);
  atomic_store_explicit(&buffer->write_cursor, 0, memory_order_release);
  atomic_store_explicit(&buffer->trim_target_frames, AF_NO_TRIM_REQUEST, memory_order_release);
  atomic_store_explicit(&buffer->primed, false, memory_order_release);
  atomic_store_explicit(&buffer->total_written_frames, 0, memory_order_relaxed);
  atomic_store_explicit(&buffer->total_read_frames, 0, memory_order_relaxed);
  atomic_store_explicit(&buffer->underrun_events, 0, memory_order_relaxed);
  atomic_store_explicit(&buffer->underrun_frames, 0, memory_order_relaxed);
  atomic_store_explicit(&buffer->overflow_events, 0, memory_order_relaxed);
  atomic_store_explicit(&buffer->overflow_frames, 0, memory_order_relaxed);
  atomic_store_explicit(&buffer->trimmed_frames, 0, memory_order_relaxed);
  buffer->fade_remaining = 0;
  buffer->last_left = 0;
  buffer->last_right = 0;
}

void AFAudioRingBufferSetStartupFrames(AFAudioRingBuffer *buffer, uint32_t startup_frames) {
  if (buffer == NULL) {
    return;
  }
  atomic_store_explicit(
    &buffer->startup_frames,
    af_clamp_startup(buffer, startup_frames),
    memory_order_release
  );
}

uint32_t AFAudioRingBufferWriteStereoInterleaved(
  AFAudioRingBuffer *buffer,
  const float *samples,
  uint32_t frames
) {
  if (buffer == NULL || samples == NULL || frames == 0) {
    return 0;
  }

  const uint64_t write_cursor = atomic_load_explicit(&buffer->write_cursor, memory_order_relaxed);
  const uint64_t read_cursor = atomic_load_explicit(&buffer->read_cursor, memory_order_acquire);
  const uint64_t available = write_cursor - read_cursor;
  const uint32_t free_frames = available >= buffer->capacity_frames
    ? 0
    : buffer->capacity_frames - (uint32_t)available;
  const uint32_t frames_to_write = frames < free_frames ? frames : free_frames;

  if (frames_to_write > 0) {
    const uint32_t start = (uint32_t)(write_cursor % buffer->capacity_frames);
    const uint32_t first_frames = frames_to_write < (buffer->capacity_frames - start)
      ? frames_to_write
      : buffer->capacity_frames - start;
    memcpy(
      buffer->samples + ((size_t)start * 2),
      samples,
      (size_t)first_frames * 2 * sizeof(float)
    );
    const uint32_t second_frames = frames_to_write - first_frames;
    if (second_frames > 0) {
      memcpy(
        buffer->samples,
        samples + ((size_t)first_frames * 2),
        (size_t)second_frames * 2 * sizeof(float)
      );
    }
    atomic_store_explicit(
      &buffer->write_cursor,
      write_cursor + frames_to_write,
      memory_order_release
    );
    atomic_fetch_add_explicit(
      &buffer->total_written_frames,
      frames_to_write,
      memory_order_relaxed
    );
  }

  const uint32_t dropped = frames - frames_to_write;
  if (dropped > 0) {
    atomic_fetch_add_explicit(&buffer->overflow_events, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&buffer->overflow_frames, dropped, memory_order_relaxed);
  }
  return frames_to_write;
}

uint32_t AFAudioRingBufferReadStereoPlanar(
  AFAudioRingBuffer *buffer,
  float *left,
  float *right,
  uint32_t frames
) {
  if (buffer == NULL || left == NULL || right == NULL || frames == 0) {
    return 0;
  }

  uint64_t read_cursor = atomic_load_explicit(&buffer->read_cursor, memory_order_relaxed);
  const uint64_t write_cursor = atomic_load_explicit(&buffer->write_cursor, memory_order_acquire);
  uint64_t available = write_cursor - read_cursor;

  const uint32_t trim_target = atomic_exchange_explicit(
    &buffer->trim_target_frames,
    AF_NO_TRIM_REQUEST,
    memory_order_acq_rel
  );
  if (trim_target != AF_NO_TRIM_REQUEST && available > trim_target) {
    const uint64_t trimmed = available - trim_target;
    read_cursor += trimmed;
    available = trim_target;
    atomic_store_explicit(&buffer->read_cursor, read_cursor, memory_order_release);
    atomic_fetch_add_explicit(&buffer->trimmed_frames, trimmed, memory_order_relaxed);
    buffer->fade_remaining = buffer->fade_frames;
  }

  bool primed = atomic_load_explicit(&buffer->primed, memory_order_acquire);
  if (!primed) {
    const uint32_t startup = atomic_load_explicit(&buffer->startup_frames, memory_order_acquire);
    if (available < startup) {
      af_zero(left, right, 0, frames);
      return 0;
    }
    primed = true;
    atomic_store_explicit(&buffer->primed, true, memory_order_release);
    buffer->fade_remaining = buffer->fade_frames;
  }

  const uint32_t frames_to_read = available < frames ? (uint32_t)available : frames;
  for (uint32_t frame = 0; frame < frames_to_read; frame++) {
    const uint32_t source_frame = (uint32_t)((read_cursor + frame) % buffer->capacity_frames);
    float left_sample = buffer->samples[(size_t)source_frame * 2];
    float right_sample = buffer->samples[(size_t)source_frame * 2 + 1];
    if (buffer->fade_remaining > 0 && buffer->fade_frames > 0) {
      const float gain = 1.0f - ((float)buffer->fade_remaining / (float)buffer->fade_frames);
      left_sample *= gain;
      right_sample *= gain;
      buffer->fade_remaining--;
    }
    left[frame] = left_sample;
    right[frame] = right_sample;
    buffer->last_left = left_sample;
    buffer->last_right = right_sample;
  }

  read_cursor += frames_to_read;
  atomic_store_explicit(&buffer->read_cursor, read_cursor, memory_order_release);
  atomic_fetch_add_explicit(&buffer->total_read_frames, frames_to_read, memory_order_relaxed);

  if (frames_to_read < frames) {
    const uint32_t missing = frames - frames_to_read;
    const uint32_t ramp_frames = missing < 64 ? missing : 64;
    for (uint32_t frame = 0; frame < ramp_frames; frame++) {
      const float gain = 1.0f - ((float)(frame + 1) / (float)ramp_frames);
      left[frames_to_read + frame] = buffer->last_left * gain;
      right[frames_to_read + frame] = buffer->last_right * gain;
    }
    af_zero(left, right, frames_to_read + ramp_frames, missing - ramp_frames);
    atomic_fetch_add_explicit(&buffer->underrun_events, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&buffer->underrun_frames, missing, memory_order_relaxed);
    atomic_store_explicit(&buffer->primed, false, memory_order_release);
    buffer->last_left = 0;
    buffer->last_right = 0;
  }

  return frames_to_read;
}

void AFAudioRingBufferRequestTrim(AFAudioRingBuffer *buffer, uint32_t frames_to_keep) {
  if (buffer == NULL) {
    return;
  }
  atomic_store_explicit(
    &buffer->trim_target_frames,
    frames_to_keep < buffer->capacity_frames ? frames_to_keep : buffer->capacity_frames,
    memory_order_release
  );
}

AFAudioRingBufferStats AFAudioRingBufferGetStats(const AFAudioRingBuffer *buffer) {
  AFAudioRingBufferStats stats = {0};
  if (buffer == NULL) {
    return stats;
  }
  const uint64_t read_cursor = atomic_load_explicit(&buffer->read_cursor, memory_order_acquire);
  const uint64_t write_cursor = atomic_load_explicit(&buffer->write_cursor, memory_order_acquire);
  const uint64_t available = write_cursor - read_cursor;
  stats.capacity_frames = buffer->capacity_frames;
  stats.available_frames = available > buffer->capacity_frames
    ? buffer->capacity_frames
    : (uint32_t)available;
  stats.startup_frames = atomic_load_explicit(&buffer->startup_frames, memory_order_acquire);
  stats.total_written_frames = atomic_load_explicit(&buffer->total_written_frames, memory_order_relaxed);
  stats.total_read_frames = atomic_load_explicit(&buffer->total_read_frames, memory_order_relaxed);
  stats.underrun_events = atomic_load_explicit(&buffer->underrun_events, memory_order_relaxed);
  stats.underrun_frames = atomic_load_explicit(&buffer->underrun_frames, memory_order_relaxed);
  stats.overflow_events = atomic_load_explicit(&buffer->overflow_events, memory_order_relaxed);
  stats.overflow_frames = atomic_load_explicit(&buffer->overflow_frames, memory_order_relaxed);
  stats.trimmed_frames = atomic_load_explicit(&buffer->trimmed_frames, memory_order_relaxed);
  stats.primed = atomic_load_explicit(&buffer->primed, memory_order_acquire);
  return stats;
}
