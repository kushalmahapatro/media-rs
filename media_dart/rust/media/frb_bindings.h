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

typedef struct wire_cst_timeline_thumbnail {
  uint32_t index;
  double time_sec;
  struct wire_cst_list_prim_u_8_strict *image_bytes;
} wire_cst_timeline_thumbnail;

typedef struct wire_cst_transcode_progress {
  struct wire_cst_list_prim_u_8_strict *phase;
  double fraction;
  struct wire_cst_list_prim_u_8_strict *message;
} wire_cst_transcode_progress;

typedef struct wire_cst_video_probe {
  int64_t *duration_ms;
  uint32_t *width;
  uint32_t *height;
  int64_t *video_bitrate;
  int64_t *audio_bitrate;
  double *frame_rate;
  struct wire_cst_list_prim_u_8_strict *video_codec;
  struct wire_cst_list_prim_u_8_strict *audio_codec;
} wire_cst_video_probe;

void frbgen_media_wire__crate__api__probe_video(int64_t port_,
                                                         struct wire_cst_list_prim_u_8_strict *path);

void frbgen_media_wire__crate__api__thumbnail_image(int64_t port_,
                                                             struct wire_cst_list_prim_u_8_strict *path,
                                                             double time_sec,
                                                             uint32_t max_edge,
                                                             int32_t format);

void frbgen_media_wire__crate__api__thumbnail_save_to_path(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *path,
                                                                    struct wire_cst_list_prim_u_8_strict *output_path,
                                                                    double time_sec,
                                                                    uint32_t max_edge,
                                                                    int32_t format);

void frbgen_media_wire__crate__api__timeline_thumbnails(int64_t port_,
                                                                 struct wire_cst_list_prim_u_8_strict *path,
                                                                 uint32_t frame_count,
                                                                 uint32_t max_edge,
                                                                 int32_t format,
                                                                 struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_media_wire__crate__api__transcode_video(int64_t port_,
                                                             struct wire_cst_list_prim_u_8_strict *input_path,
                                                             struct wire_cst_list_prim_u_8_strict *output_path,
                                                             uint32_t video_bitrate_kbps,
                                                             uint32_t max_width,
                                                             uint32_t audio_bitrate_kbps,
                                                             struct wire_cst_list_prim_u_8_strict *sink);

double *frbgen_media_cst_new_box_autoadd_f_64(double value);

int64_t *frbgen_media_cst_new_box_autoadd_i_64(int64_t value);

uint32_t *frbgen_media_cst_new_box_autoadd_u_32(uint32_t value);

struct wire_cst_list_prim_u_8_strict *frbgen_media_cst_new_list_prim_u_8_strict(int32_t len);
static int64_t dummy_method_to_enforce_bundling(void) {
    int64_t dummy_var = 0;
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_f_64);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_i_64);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_u_32);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__probe_video);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__thumbnail_image);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__thumbnail_save_to_path);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__timeline_thumbnails);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__transcode_video);
    dummy_var ^= ((int64_t) (void*) store_dart_post_cobject);
    return dummy_var;
}
