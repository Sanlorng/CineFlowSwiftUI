#ifndef ffmpeg_lite_h
#define ffmpeg_lite_h

#include <stdint.h>
#include <stddef.h>

#define AV_NOPTS_VALUE ((int64_t)UINT64_C(0x8000000000000000))

typedef struct AVClass AVClass;
typedef struct AVBufferRef AVBufferRef;
typedef struct AVPacketSideData AVPacketSideData;
typedef struct AVCodec AVCodec;
typedef struct AVCodecInternal AVCodecInternal;
typedef struct AVDictionary AVDictionary;
typedef struct AVDictionaryEntry {
    char *key;
    char *value;
} AVDictionaryEntry;
typedef struct AVInputFormat AVInputFormat;
typedef struct AVOutputFormat AVOutputFormat;
typedef struct AVIOContext AVIOContext;

typedef struct AVRational {
    int num;
    int den;
} AVRational;

typedef int AVCodecID;

typedef enum AVMediaType {
    AVMEDIA_TYPE_UNKNOWN = -1,
    AVMEDIA_TYPE_VIDEO = 0,
    AVMEDIA_TYPE_AUDIO = 1,
    AVMEDIA_TYPE_DATA = 2,
    AVMEDIA_TYPE_SUBTITLE = 3,
    AVMEDIA_TYPE_ATTACHMENT = 4,
} AVMediaType;

typedef enum AVSubtitleType {
    SUBTITLE_NONE = 0,
    SUBTITLE_BITMAP = 1,
    SUBTITLE_TEXT = 2,
    SUBTITLE_ASS = 3,
} AVSubtitleType;

typedef struct AVPacket {
    AVBufferRef *buf;
    int64_t pts;
    int64_t dts;
    uint8_t *data;
    int size;
    int stream_index;
    int flags;
    AVPacketSideData *side_data;
    int side_data_elems;
    int64_t duration;
    int64_t pos;
    void *opaque;
    AVBufferRef *opaque_ref;
    AVRational time_base;
} AVPacket;

typedef struct AVCodecParameters {
    AVMediaType codec_type;
    AVCodecID codec_id;
    uint32_t codec_tag;
    uint8_t *extradata;
    int extradata_size;
} AVCodecParameters;

typedef struct AVStream {
    const AVClass *av_class;
    int index;
    int id;
    AVCodecParameters *codecpar;
    void *priv_data;
    AVRational time_base;
    int64_t start_time;
    int64_t duration;
    int64_t nb_frames;
    int disposition;
    int discard;
    AVRational sample_aspect_ratio;
    AVDictionary *metadata;
} AVStream;

typedef struct AVFormatContext {
    const AVClass *av_class;
    const AVInputFormat *iformat;
    const AVOutputFormat *oformat;
    void *priv_data;
    AVIOContext *pb;
    int ctx_flags;
    unsigned int nb_streams;
    AVStream **streams;
} AVFormatContext;

typedef struct AVCodecContext {
    const AVClass *av_class;
    int log_level_offset;
    AVMediaType codec_type;
    const AVCodec *codec;
    AVCodecID codec_id;
    unsigned int codec_tag;
    void *priv_data;
    AVCodecInternal *internal;
    void *opaque;
    int64_t bit_rate;
    int flags;
    int flags2;
    uint8_t *extradata;
    int extradata_size;
    AVRational time_base;
    AVRational pkt_timebase;
    AVRational framerate;
    int ticks_per_frame;
    int delay;
} AVCodecContext;

typedef struct AVSubtitleRect {
    int x;
    int y;
    int w;
    int h;
    int nb_colors;
    uint8_t *data[4];
    int linesize[4];
    int flags;
    AVSubtitleType type;
    char *text;
    char *ass;
} AVSubtitleRect;

typedef struct AVSubtitle {
    uint16_t format;
    uint32_t start_display_time;
    uint32_t end_display_time;
    unsigned num_rects;
    AVSubtitleRect **rects;
    int64_t pts;
} AVSubtitle;

int avformat_network_init(void);
int avformat_open_input(AVFormatContext **ps, const char *url, const AVInputFormat *fmt, AVDictionary **options);
int avformat_find_stream_info(AVFormatContext *ic, AVDictionary **options);
void avformat_close_input(AVFormatContext **s);
int av_read_frame(AVFormatContext *s, AVPacket *pkt);

const AVCodec *avcodec_find_decoder(AVCodecID id);
const char *avcodec_get_name(AVCodecID id);
AVCodecContext *avcodec_alloc_context3(const AVCodec *codec);
int avcodec_parameters_to_context(AVCodecContext *codec, const AVCodecParameters *par);
int avcodec_open2(AVCodecContext *avctx, const AVCodec *codec, AVDictionary **options);
int avcodec_decode_subtitle2(AVCodecContext *avctx, AVSubtitle *sub, int *got_sub_ptr, const AVPacket *avpkt);
void avcodec_free_context(AVCodecContext **avctx);
void avcodec_flush_buffers(AVCodecContext *avctx);

AVPacket *av_packet_alloc(void);
void av_packet_free(AVPacket **pkt);
void av_packet_unref(AVPacket *pkt);

int av_dict_set(AVDictionary **pm, const char *key, const char *value, int flags);
void av_dict_free(AVDictionary **m);
AVDictionaryEntry *av_dict_get(const AVDictionary *m, const char *key, const AVDictionaryEntry *prev, int flags);

void avsubtitle_free(AVSubtitle *sub);

#endif
