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

typedef struct wire_cst_compress_params {
  uint32_t target_bitrate_kbps;
  struct wire_cst_list_prim_u_8_strict *preset;
  uint8_t *crf;
  uint32_t *width;
  uint32_t *height;
  uint64_t *sample_duration_ms;
} wire_cst_compress_params;

typedef struct wire_cst_record_u_32_u_32 {
  uint32_t field0;
  uint32_t field1;
} wire_cst_record_u_32_u_32;

typedef struct wire_cst_ThumbnailSizeType_Custom {
  struct wire_cst_record_u_32_u_32 *field0;
} wire_cst_ThumbnailSizeType_Custom;

typedef union ThumbnailSizeTypeKind {
  struct wire_cst_ThumbnailSizeType_Custom Custom;
} ThumbnailSizeTypeKind;

typedef struct wire_cst_thumbnail_size_type {
  int32_t tag;
  union ThumbnailSizeTypeKind kind;
} wire_cst_thumbnail_size_type;

typedef struct wire_cst_image_thumbnail_params {
  struct wire_cst_thumbnail_size_type *size_type;
  int32_t *format;
} wire_cst_image_thumbnail_params;

typedef struct wire_cst_video_thumbnail_params {
  uint64_t time_ms;
  struct wire_cst_thumbnail_size_type *size_type;
  int32_t *format;
} wire_cst_video_thumbnail_params;

typedef struct wire_cst_write_to_files {
  struct wire_cst_list_prim_u_8_strict *path;
  struct wire_cst_list_prim_u_8_strict *file_prefix;
  struct wire_cst_list_prim_u_8_strict *file_suffix;
  uint64_t *max_files;
} wire_cst_write_to_files;

typedef struct wire_cst_resolution_preset {
  struct wire_cst_list_prim_u_8_strict *name;
  uint32_t width;
  uint32_t height;
  uint64_t bitrate;
  uint8_t crf;
} wire_cst_resolution_preset;

typedef struct wire_cst_list_resolution_preset {
  struct wire_cst_resolution_preset *ptr;
  int32_t len;
} wire_cst_list_resolution_preset;

typedef struct wire_cst_compression_estimate {
  uint64_t estimated_size_bytes;
  uint64_t estimated_duration_ms;
} wire_cst_compression_estimate;

typedef struct wire_cst_video_info {
  uint64_t duration_ms;
  uint32_t width;
  uint32_t height;
  uint64_t size_bytes;
  uint64_t *bitrate;
  struct wire_cst_list_prim_u_8_strict *codec_name;
  struct wire_cst_list_prim_u_8_strict *format_name;
  struct wire_cst_list_resolution_preset *suggestions;
} wire_cst_video_info;

void frbgen_media_wire__crate__api__media__compress_video(int64_t port_,
                                                          struct wire_cst_list_prim_u_8_strict *path,
                                                          struct wire_cst_list_prim_u_8_strict *output_path,
                                                          struct wire_cst_compress_params *params);

void frbgen_media_wire__crate__api__logger__debug_threads(int64_t port_);

void frbgen_media_wire__crate__api__media__estimate_compression(int64_t port_,
                                                                struct wire_cst_list_prim_u_8_strict *path,
                                                                struct wire_cst_list_prim_u_8_strict *temp_output_path,
                                                                struct wire_cst_compress_params *params);

void frbgen_media_wire__crate__api__media__generate_image_thumbnail(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *path,
                                                                    struct wire_cst_list_prim_u_8_strict *output_path,
                                                                    struct wire_cst_image_thumbnail_params *params,
                                                                    struct wire_cst_list_prim_u_8_strict *suffix);

void frbgen_media_wire__crate__api__media__generate_video_thumbnail(int64_t port_,
                                                                    struct wire_cst_list_prim_u_8_strict *path,
                                                                    struct wire_cst_list_prim_u_8_strict *output_path,
                                                                    struct wire_cst_video_thumbnail_params *params,
                                                                    bool *empty_image_fallback);

void frbgen_media_wire__crate__api__media__generate_video_timeline_thumbnails(int64_t port_,
                                                                              struct wire_cst_list_prim_u_8_strict *path,
                                                                              struct wire_cst_list_prim_u_8_strict *output_path,
                                                                              struct wire_cst_image_thumbnail_params *params,
                                                                              uint32_t num_thumbnails,
                                                                              bool *empty_image_fallback,
                                                                              struct wire_cst_list_prim_u_8_strict *sink);

void frbgen_media_wire__crate__api__media__get_video_info(int64_t port_,
                                                          struct wire_cst_list_prim_u_8_strict *path);

void frbgen_media_wire__crate__api__logger__init_logger(int64_t port_,
                                                        int32_t log_level,
                                                        bool write_to_stdout_or_system,
                                                        struct wire_cst_write_to_files *write_to_files,
                                                        bool use_lightweight_tokio_runtime);

void frbgen_media_wire__crate__api__logger__log(int64_t port_,
                                                struct wire_cst_list_prim_u_8_strict *file,
                                                uint32_t *line,
                                                int32_t level,
                                                struct wire_cst_list_prim_u_8_strict *target,
                                                struct wire_cst_list_prim_u_8_strict *message);

void frbgen_media_wire__crate__api__media__output_format_extension(int64_t port_, int32_t that);

void frbgen_media_wire__crate__api__logger__reload_tracing_file_writer(int64_t port_,
                                                                       struct wire_cst_write_to_files *write_to_files);

void frbgen_media_wire__crate__api__media__thumbnail_size_type_dimensions(int64_t port_,
                                                                          struct wire_cst_thumbnail_size_type *that);

bool *frbgen_media_cst_new_box_autoadd_bool(bool value);

struct wire_cst_compress_params *frbgen_media_cst_new_box_autoadd_compress_params(void);

struct wire_cst_image_thumbnail_params *frbgen_media_cst_new_box_autoadd_image_thumbnail_params(void);

int32_t *frbgen_media_cst_new_box_autoadd_output_format(int32_t value);

struct wire_cst_record_u_32_u_32 *frbgen_media_cst_new_box_autoadd_record_u_32_u_32(void);

struct wire_cst_thumbnail_size_type *frbgen_media_cst_new_box_autoadd_thumbnail_size_type(void);

uint32_t *frbgen_media_cst_new_box_autoadd_u_32(uint32_t value);

uint64_t *frbgen_media_cst_new_box_autoadd_u_64(uint64_t value);

uint8_t *frbgen_media_cst_new_box_autoadd_u_8(uint8_t value);

struct wire_cst_video_thumbnail_params *frbgen_media_cst_new_box_autoadd_video_thumbnail_params(void);

struct wire_cst_write_to_files *frbgen_media_cst_new_box_autoadd_write_to_files(void);

struct wire_cst_list_prim_u_8_strict *frbgen_media_cst_new_list_prim_u_8_strict(int32_t len);

struct wire_cst_list_resolution_preset *frbgen_media_cst_new_list_resolution_preset(int32_t len);
static int64_t dummy_method_to_enforce_bundling(void) {
    int64_t dummy_var = 0;
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_bool);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_compress_params);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_image_thumbnail_params);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_output_format);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_record_u_32_u_32);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_thumbnail_size_type);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_u_32);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_u_64);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_u_8);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_video_thumbnail_params);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_box_autoadd_write_to_files);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_list_prim_u_8_strict);
    dummy_var ^= ((int64_t) (void*) frbgen_media_cst_new_list_resolution_preset);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__logger__debug_threads);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__logger__init_logger);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__logger__log);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__logger__reload_tracing_file_writer);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__compress_video);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__estimate_compression);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__generate_image_thumbnail);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__generate_video_thumbnail);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__generate_video_timeline_thumbnails);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__get_video_info);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__output_format_extension);
    dummy_var ^= ((int64_t) (void*) frbgen_media_wire__crate__api__media__thumbnail_size_type_dimensions);
    dummy_var ^= ((int64_t) (void*) store_dart_post_cobject);
    return dummy_var;
}
