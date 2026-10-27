#include "MediaPreviewBridge.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <math.h>
struct MediaPreviewRequest { atomic_bool cancelled; double deadline; };
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
MediaPreviewRequest *media_preview_request_create(void) {
    MediaPreviewRequest *r = calloc(1, sizeof(*r));
    if (r) { atomic_init(&r->cancelled, 0); r->deadline = now() + 8; }
    return r;
}
void media_preview_request_cancel(MediaPreviewRequest *r) { if (r) atomic_store(&r->cancelled, 1); }
void media_preview_request_free(MediaPreviewRequest *r) { free(r); }
static int interrupted(void *opaque) { MediaPreviewRequest *r = opaque; return !r || atomic_load(&r->cancelled) || now() > r->deadline; }
static AVFormatContext *open_media(MediaPreviewRequest *r, const char *url, const char *headers, int bypass) {
    if (interrupted(r)) return NULL;
    AVFormatContext *f = avformat_alloc_context();
    if (!f) return NULL;
    f->interrupt_callback = (AVIOInterruptCB){ interrupted, r };
    AVDictionary *opts = NULL;
    av_dict_set(&opts, "rw_timeout", "5000000", 0);
    av_dict_set(&opts, "probesize", "2097152", 0);
    av_dict_set(&opts, "analyzeduration", "2000000", 0);
    if (headers && *headers) av_dict_set(&opts, "headers", headers, 0);
    if (bypass) av_dict_set(&opts, "http_proxy", "", 0);
    int result = avformat_open_input(&f, url, NULL, &opts);
    av_dict_free(&opts);
    if (result < 0) { avformat_close_input(&f); return NULL; }
    return f;
}
int media_preview_chapters(MediaPreviewRequest *r, const char *url, const char *headers, int bypass, MediaPreviewChapter **out, int *count) {
    *out = NULL; *count = 0;
    AVFormatContext *f = open_media(r, url, headers, bypass);
    if (!f) return -1;
    int n = (int)f->nb_chapters;
    if (n > 10000) { avformat_close_input(&f); return -1; }
    MediaPreviewChapter *items = n ? calloc(n, sizeof(*items)) : NULL;
    if (n && !items) { avformat_close_input(&f); return -1; }
    for (int i = 0; i < n; i++) {
        AVChapter *c = f->chapters[i];
        items[i].time = c->start * av_q2d(c->time_base);
        AVDictionaryEntry *title = av_dict_get(c->metadata, "title", NULL, 0);
        items[i].title = strdup(title ? title->value : "");
    }
    avformat_close_input(&f);
    *out = items; *count = n;
    return 0;
}
void media_preview_chapters_free(MediaPreviewChapter *items, int n) {
    for (int i = 0; i < n; i++) free(items[i].title);
    free(items);
}
void media_preview_frame_free(MediaPreviewFrame *frame) { free(frame->pixels); frame->pixels = NULL; }
int media_preview_frame(MediaPreviewRequest *r, const char *url, const char *headers, int bypass, double time, MediaPreviewFrame *out) {
    memset(out, 0, sizeof(*out));
    if (!isfinite(time) || time < 0) return -1;
    AVFormatContext *f = open_media(r, url, headers, bypass);
    if (!f) return -1;
    AVCodecContext *decoder = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    struct SwsContext *scale = NULL;
    int result = -1;
    if (avformat_find_stream_info(f, NULL) < 0 || interrupted(r)) goto done;
    const AVCodec *codec = NULL;
    int stream = av_find_best_stream(f, AVMEDIA_TYPE_VIDEO, -1, -1, &codec, 0);
    if (stream < 0 || !codec) goto done;
    AVStream *s = f->streams[stream];
    decoder = avcodec_alloc_context3(codec);
    if (!decoder || avcodec_parameters_to_context(decoder, s->codecpar) < 0) goto done;
    av_opt_set_int(decoder, "threads", 1, 0);
    if (avcodec_open2(decoder, codec, NULL) < 0) goto done;
    double origin = s->start_time == AV_NOPTS_VALUE ? 0 : s->start_time * av_q2d(s->time_base);
    int64_t target = (int64_t)((time + origin) / av_q2d(s->time_base));
    if (av_seek_frame(f, stream, target, AVSEEK_FLAG_BACKWARD) < 0) goto done;
    avcodec_flush_buffers(decoder);
    packet = av_packet_alloc(); frame = av_frame_alloc();
    if (!packet || !frame) goto done;
    // Decode at most a bounded GOP. Preview failures never affect playback.
    for (int i = 0; i < 600 && !interrupted(r); i++) {
        if (av_read_frame(f, packet) < 0) break;
        if (packet->stream_index == stream && avcodec_send_packet(decoder, packet) >= 0) {
            while (!interrupted(r) && avcodec_receive_frame(decoder, frame) >= 0) {
                double actual = frame->best_effort_timestamp == AV_NOPTS_VALUE ? time : frame->best_effort_timestamp * av_q2d(s->time_base) - origin;
                if (actual + 0.1 < time) continue;
                if (frame->width <= 0 || frame->height <= 0) goto done;
                double ratio = fmin(320.0 / frame->width, 180.0 / frame->height);
                out->width = fmax(1, round(frame->width * ratio));
                out->height = fmax(1, round(frame->height * ratio));
                out->pixels = malloc(out->width * out->height * 4);
                if (!out->pixels) goto done;
                scale = sws_getContext(frame->width, frame->height, frame->format, out->width, out->height, AV_PIX_FMT_RGBA, SWS_BILINEAR, NULL, NULL, NULL);
                if (!scale) goto done;
                uint8_t *data[4] = {out->pixels}; int lines[4] = {out->width * 4};
                if (sws_scale(scale, (const uint8_t * const *)frame->data, frame->linesize, 0, frame->height, data, lines) <= 0) goto done;
                out->time = fmax(0, actual); result = 0; goto done;
            }
        }
        av_packet_unref(packet);
    }
done:
    sws_freeContext(scale);
    av_frame_free(&frame); av_packet_free(&packet); avcodec_free_context(&decoder); avformat_close_input(&f);
    if (result != 0) media_preview_frame_free(out);
    return result;
}
