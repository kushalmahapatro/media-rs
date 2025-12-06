#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
// EXTRA BEGIN
typedef struct DartCObject *WireSyncRust2DartDco;
typedef struct WireSyncRust2DartSse {
  uint8_t *ptr;
  int32_t len;
} WireSyncRust2DartSse;

typedef int64_t DartPort;
typedef bool (*DartPostCObjectFnType)(DartPort port_id, void *message);
void store_dart_post_cobject(DartPostCObjectFnType ptr);
// EXTRA END
typedef struct _Dart_Handle* Dart_Handle;

typedef struct wire_cst_list_prim_u_8_strict {
  uint8_t *ptr;
  int32_t len;
} wire_cst_list_prim_u_8_strict;

typedef struct wire_cst_thumbnail_params {
  uint64_t time_ms;
  uint32_t max_width;
  uint32_t max_height;
} wire_cst_thumbnail_params;

typedef struct CVideoInfo {
  uint64_t duration_ms;
  uint32_t width;
  uint32_t height;
  uint64_t size_bytes;
  bool has_bitrate;
  uint64_t bitrate;
  char *codec_name;
  char *format_name;
} CVideoInfo;

typedef struct CBuffer {
  uint8_t *data;
  uint64_t len;
} CBuffer;

typedef struct wire_cst_video_info {
  uint64_t duration_ms;
  uint32_t width;
  uint32_t height;
  uint64_t size_bytes;
  uint64_t *bitrate;
  struct wire_cst_list_prim_u_8_strict *codec_name;
  struct wire_cst_list_prim_u_8_strict *format_name;
} wire_cst_video_info;

void frbgen_media_wire__crate__api__media__generate_thumbnail(int64_t port_,
                                                              struct wire_cst_list_prim_u_8_strict *path,
                                                              struct wire_cst_thumbnail_params *params);

void frbgen_media_wire__crate__api__media__get_video_info(int64_t port_,
                                                          struct wire_cst_list_prim_u_8_strict *path);

struct wire_cst_thumbnail_params *frbgen_media_cst_new_box_autoadd_thumbnail_params(void);

uint64_t *frbgen_media_cst_new_box_autoadd_u_64(uint64_t value);

struct wire_cst_list_prim_u_8_strict *frbgen_media_cst_new_list_prim_u_8_strict(int32_t len);

struct CVideoInfo *media_get_video_info(const char *path);

struct CBuffer *media_generate_thumbnail(const char *path,
                                         uint64_t time_ms,
                                         uint32_t max_width,
                                         uint32_t max_height);

void media_free_video_info(struct CVideoInfo *ptr);

void media_free_buffer(struct CBuffer *ptr);
static int64_t dummy_method_to_enforce_bundling(void) {
    int64_t dummy_var = 0;
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_thumbnail_params);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_u_64);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__generate_thumbnail);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__get_video_info);
    dummy_var ^= ((int64_t) (void*) store_dart_post_cobject);
    return dummy_var;
}
