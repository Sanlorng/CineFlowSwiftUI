#include "SubtitleFFmpegBridge.h"
#include "ffmpeg_lite.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if __has_include("ffmpeg_lite.h")

typedef struct BridgeStringBuilder {
    char *data;
    size_t length;
    size_t capacity;
} BridgeStringBuilder;

static void bridge_builder_free(BridgeStringBuilder *builder) {
    if (builder->data) {
        free(builder->data);
        builder->data = NULL;
    }
    builder->length = 0;
    builder->capacity = 0;
}

static int bridge_builder_reserve(BridgeStringBuilder *builder, size_t extra) {
    size_t needed = builder->length + extra + 1;
    if (needed <= builder->capacity) {
        return 0;
    }
    size_t capacity = builder->capacity == 0 ? 1024 : builder->capacity;
    while (capacity < needed) {
        capacity *= 2;
    }
    char *newData = realloc(builder->data, capacity);
    if (!newData) {
        return -1;
    }
    builder->data = newData;
    builder->capacity = capacity;
    return 0;
}

static int bridge_builder_append_data(BridgeStringBuilder *builder, const char *data, size_t length) {
    if (bridge_builder_reserve(builder, length) < 0) {
        return -1;
    }
    memcpy(builder->data + builder->length, data, length);
    builder->length += length;
    builder->data[builder->length] = '\0';
    return 0;
}

static int bridge_builder_append_string(BridgeStringBuilder *builder, const char *string) {
    if (!string) {
        return 0;
    }
    return bridge_builder_append_data(builder, string, strlen(string));
}

static int bridge_builder_append_format(BridgeStringBuilder *builder, const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    va_list copied;
    va_copy(copied, arguments);
    int length = vsnprintf(NULL, 0, format, copied);
    va_end(copied);
    if (length < 0) {
        va_end(arguments);
        return -1;
    }
    if (bridge_builder_reserve(builder, (size_t) length) < 0) {
        va_end(arguments);
        return -1;
    }
    vsnprintf(builder->data + builder->length, (size_t) length + 1, format, arguments);
    builder->length += (size_t) length;
    va_end(arguments);
    return 0;
}

static char *bridge_strdup(const char *string) {
    if (!string) {
        return NULL;
    }
    size_t length = strlen(string) + 1;
    char *result = malloc(length);
    if (!result) {
        return NULL;
    }
    memcpy(result, string, length);
    return result;
}

static void bridge_set_error(char **error_message, const char *format, ...) {
    if (!error_message) {
        return;
    }
    *error_message = NULL;

    va_list arguments;
    va_start(arguments, format);
    va_list copied;
    va_copy(copied, arguments);
    int length = vsnprintf(NULL, 0, format, copied);
    va_end(copied);
    if (length < 0) {
        va_end(arguments);
        return;
    }
    char *buffer = malloc((size_t) length + 1);
    if (!buffer) {
        va_end(arguments);
        return;
    }
    vsnprintf(buffer, (size_t) length + 1, format, arguments);
    va_end(arguments);
    *error_message = buffer;
}

static int bridge_open_input(
    const char *media_url,
    const char *headers,
    AVFormatContext **format_context,
    char **error_message
) {
    *format_context = NULL;
    avformat_network_init();

    AVDictionary *options = NULL;
    if (headers && headers[0] != '\0') {
        av_dict_set(&options, "headers", headers, 0);
    }

    int result = avformat_open_input(format_context, media_url, NULL, &options);
    av_dict_free(&options);
    if (result < 0 || !*format_context) {
        bridge_set_error(error_message, "打开媒体失败。");
        return -1;
    }

    result = avformat_find_stream_info(*format_context, NULL);
    if (result < 0) {
        bridge_set_error(error_message, "读取媒体流信息失败。");
        avformat_close_input(format_context);
        return -1;
    }

    return 0;
}

static char *bridge_dict_value(AVDictionary *dictionary, const char *key) {
    AVDictionaryEntry *entry = av_dict_get(dictionary, key, NULL, 0);
    return entry ? bridge_strdup(entry->value) : NULL;
}

static const char *bridge_default_ass_header =
    "[Script Info]\n"
    "ScriptType: v4.00+\n"
    "PlayResX: 1920\n"
    "PlayResY: 1080\n"
    "ScaledBorderAndShadow: yes\n"
    "\n"
    "[V4+ Styles]\n"
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    "Style: Default,Arial,54,&H00FFFFFF,&H000000FF,&H64000000,&H64000000,0,0,0,0,100,100,0,0,1,2.2,0.8,2,80,80,54,1\n"
    "\n"
    "[Events]\n"
    "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n";

static void bridge_format_ass_time(int milliseconds, char *buffer, size_t buffer_size) {
    int total_centiseconds = milliseconds / 10;
    int centiseconds = total_centiseconds % 100;
    int total_seconds = total_centiseconds / 100;
    int seconds = total_seconds % 60;
    int total_minutes = total_seconds / 60;
    int minutes = total_minutes % 60;
    int hours = total_minutes / 60;
    snprintf(buffer, buffer_size, "%d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds);
}

static int64_t bridge_pts_to_milliseconds(int64_t pts, AVRational time_base) {
    if (pts == AV_NOPTS_VALUE || time_base.den == 0) {
        return -1;
    }
    return (pts * (int64_t) time_base.num * 1000) / (int64_t) time_base.den;
}

static int bridge_append_ass_text(BridgeStringBuilder *builder, const char *text) {
    for (const char *cursor = text; cursor && *cursor; cursor++) {
        switch (*cursor) {
            case '\\':
                if (bridge_builder_append_string(builder, "\\\\") < 0) return -1;
                break;
            case '{':
                if (bridge_builder_append_string(builder, "｛") < 0) return -1;
                break;
            case '}':
                if (bridge_builder_append_string(builder, "｝") < 0) return -1;
                break;
            case '\r':
                break;
            case '\n':
                if (bridge_builder_append_string(builder, "\\N") < 0) return -1;
                break;
            default:
                if (bridge_builder_append_data(builder, cursor, 1) < 0) return -1;
                break;
        }
    }
    return 0;
}

static int bridge_append_text_dialogue(
    BridgeStringBuilder *builder,
    const char *text,
    int64_t subtitle_pts,
    int64_t packet_pts,
    AVRational time_base,
    uint32_t start_display_time,
    uint32_t end_display_time
) {
    int64_t base = subtitle_pts != AV_NOPTS_VALUE ? (subtitle_pts / 1000) : bridge_pts_to_milliseconds(packet_pts, time_base);
    if (base < 0) {
        base = 0;
    }

    int start_ms = (int) (base + start_display_time);
    int end_ms = (int) (base + (end_display_time > start_display_time ? end_display_time : (start_display_time + 1000)));

    char start_buffer[32];
    char end_buffer[32];
    bridge_format_ass_time(start_ms, start_buffer, sizeof(start_buffer));
    bridge_format_ass_time(end_ms, end_buffer, sizeof(end_buffer));

    if (bridge_builder_append_format(builder, "Dialogue: 0,%s,%s,Default,,0,0,0,,", start_buffer, end_buffer) < 0) {
        return -1;
    }
    if (bridge_append_ass_text(builder, text) < 0) {
        return -1;
    }
    return bridge_builder_append_string(builder, "\n");
}

int subtitle_bridge_copy_tracks(
    const char *media_url,
    const char *headers,
    SubtitleBridgeTrackInfo **tracks,
    int *count,
    char **error_message
) {
    *tracks = NULL;
    *count = 0;
    if (error_message) {
        *error_message = NULL;
    }

    AVFormatContext *format_context = NULL;
    if (bridge_open_input(media_url, headers, &format_context, error_message) < 0) {
        return -1;
    }

    SubtitleBridgeTrackInfo *items = calloc(format_context->nb_streams, sizeof(SubtitleBridgeTrackInfo));
    if (!items) {
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "分配字幕轨内存失败。");
        return -1;
    }

    int subtitle_count = 0;
    for (unsigned int index = 0; index < format_context->nb_streams; index++) {
        AVStream *stream = format_context->streams[index];
        if (!stream || !stream->codecpar || stream->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) {
            continue;
        }

        SubtitleBridgeTrackInfo *item = &items[subtitle_count++];
        item->stream_index = stream->index;
        item->codec_name = bridge_strdup(avcodec_get_name(stream->codecpar->codec_id));
        item->language = bridge_dict_value(stream->metadata, "language");
        item->title = bridge_dict_value(stream->metadata, "title");
    }

    avformat_close_input(&format_context);

    if (subtitle_count == 0) {
        free(items);
        return 0;
    }

    *tracks = items;
    *count = subtitle_count;
    return 0;
}

int subtitle_bridge_copy_ass_document(
    const char *media_url,
    const char *headers,
    int stream_index,
    char **ass_document,
    char **error_message
) {
    *ass_document = NULL;
    if (error_message) {
        *error_message = NULL;
    }

    AVFormatContext *format_context = NULL;
    if (bridge_open_input(media_url, headers, &format_context, error_message) < 0) {
        return -1;
    }

    AVStream *target_stream = NULL;
    for (unsigned int index = 0; index < format_context->nb_streams; index++) {
        AVStream *stream = format_context->streams[index];
        if (stream && stream->index == stream_index && stream->codecpar && stream->codecpar->codec_type == AVMEDIA_TYPE_SUBTITLE) {
            target_stream = stream;
            break;
        }
    }

    if (!target_stream) {
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "找不到内嵌字幕轨。");
        return -1;
    }

    const AVCodec *codec = avcodec_find_decoder(target_stream->codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "找不到字幕解码器。");
        return -1;
    }

    AVCodecContext *codec_context = avcodec_alloc_context3(codec);
    if (!codec_context) {
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "分配字幕解码器失败。");
        return -1;
    }

    if (avcodec_parameters_to_context(codec_context, target_stream->codecpar) < 0 ||
        avcodec_open2(codec_context, codec, NULL) < 0) {
        avcodec_free_context(&codec_context);
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "打开字幕解码器失败。");
        return -1;
    }

    BridgeStringBuilder ass_header = {0};
    BridgeStringBuilder ass_events = {0};
    BridgeStringBuilder text_events = {0};

    if (codec_context->extradata && codec_context->extradata_size > 0) {
        bridge_builder_append_data(&ass_header, (const char *) codec_context->extradata, (size_t) codec_context->extradata_size);
        if (ass_header.length > 0 && ass_header.data[ass_header.length - 1] != '\n') {
            bridge_builder_append_string(&ass_header, "\n");
        }
    }

    AVPacket *packet = av_packet_alloc();
    if (!packet) {
        bridge_builder_free(&ass_header);
        bridge_builder_free(&ass_events);
        bridge_builder_free(&text_events);
        avcodec_free_context(&codec_context);
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "分配字幕包失败。");
        return -1;
    }

    bool has_ass_events = false;
    bool has_text_events = false;

    while (av_read_frame(format_context, packet) >= 0) {
        if (packet->stream_index != stream_index) {
            av_packet_unref(packet);
            continue;
        }

        AVSubtitle subtitle = {0};
        int got_subtitle = 0;
        int decode_result = avcodec_decode_subtitle2(codec_context, &subtitle, &got_subtitle, packet);
        if (decode_result >= 0 && got_subtitle) {
            for (unsigned int rect_index = 0; rect_index < subtitle.num_rects; rect_index++) {
                AVSubtitleRect *rect = subtitle.rects[rect_index];
                if (!rect) {
                    continue;
                }
                if (rect->type == SUBTITLE_ASS && rect->ass && rect->ass[0] != '\0') {
                    has_ass_events = true;
                    if (strncmp(rect->ass, "Dialogue:", 9) == 0) {
                        bridge_builder_append_string(&ass_events, rect->ass);
                    } else {
                        bridge_builder_append_string(&ass_events, "Dialogue: ");
                        bridge_builder_append_string(&ass_events, rect->ass);
                    }
                    bridge_builder_append_string(&ass_events, "\n");
                } else if (rect->text && rect->text[0] != '\0') {
                    has_text_events = true;
                    bridge_append_text_dialogue(
                        &text_events,
                        rect->text,
                        subtitle.pts,
                        packet->pts,
                        target_stream->time_base,
                        subtitle.start_display_time,
                        subtitle.end_display_time
                    );
                }
            }
            avsubtitle_free(&subtitle);
        }

        av_packet_unref(packet);
    }

    av_packet_free(&packet);
    avcodec_free_context(&codec_context);
    avformat_close_input(&format_context);

    BridgeStringBuilder final_document = {0};
    if (has_ass_events) {
        if (ass_header.length == 0) {
            bridge_builder_append_string(&ass_header, bridge_default_ass_header);
        }
        bridge_builder_append_string(&final_document, ass_header.data);
        bridge_builder_append_string(&final_document, ass_events.data);
    } else if (has_text_events) {
        bridge_builder_append_string(&final_document, bridge_default_ass_header);
        bridge_builder_append_string(&final_document, text_events.data);
    } else {
        bridge_builder_free(&ass_header);
        bridge_builder_free(&ass_events);
        bridge_builder_free(&text_events);
        bridge_set_error(error_message, "当前内嵌字幕轨暂不支持自渲染。");
        return -1;
    }

    bridge_builder_free(&ass_header);
    bridge_builder_free(&ass_events);
    bridge_builder_free(&text_events);

    *ass_document = final_document.data;
    return 0;
}

void subtitle_bridge_free_tracks(SubtitleBridgeTrackInfo *tracks, int count) {
    if (!tracks) {
        return;
    }
    for (int index = 0; index < count; index++) {
        free(tracks[index].language);
        free(tracks[index].title);
        free(tracks[index].codec_name);
    }
    free(tracks);
}

void subtitle_bridge_free_string(char *string) {
    free(string);
}

#else

int subtitle_bridge_copy_tracks(
    const char *media_url,
    const char *headers,
    SubtitleBridgeTrackInfo **tracks,
    int *count,
    char **error_message
) {
    (void) media_url;
    (void) headers;
    if (tracks) *tracks = NULL;
    if (count) *count = 0;
    if (error_message) *error_message = strdup("当前构建未包含可用的 FFmpeg 字幕提取支持。");
    return -1;
}

int subtitle_bridge_copy_ass_document(
    const char *media_url,
    const char *headers,
    int stream_index,
    char **ass_document,
    char **error_message
) {
    (void) media_url;
    (void) headers;
    (void) stream_index;
    if (ass_document) *ass_document = NULL;
    if (error_message) *error_message = strdup("当前构建未包含可用的 FFmpeg 字幕提取支持。");
    return -1;
}

void subtitle_bridge_free_tracks(SubtitleBridgeTrackInfo *tracks, int count) {
    (void) count;
    free(tracks);
}

void subtitle_bridge_free_string(char *string) {
    free(string);
}
#endif
