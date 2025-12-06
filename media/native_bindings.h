#include <stdbool.h>
#include <stdint.h>

typedef struct {
  uint64_t duration_ms;
  uint32_t width;
  uint32_t height;
  uint64_t size_bytes;
  bool has_bitrate;
  uint64_t bitrate;
  char *codec_name;
  char *format_name;
} CVideoInfo;

typedef struct {
  uint8_t *data;
  uint64_t len;
} CBuffer;

CVideoInfo *media_get_video_info(const char *path);
CBuffer *media_generate_thumbnail(const char *path, uint64_t time_ms,
                                  uint32_t max_width, uint32_t max_height);
void media_free_video_info(CVideoInfo *ptr);
void media_free_buffer(CBuffer *ptr);
