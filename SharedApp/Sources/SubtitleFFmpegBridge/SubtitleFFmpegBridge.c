#include "SubtitleFFmpegBridge.h"
#include "ffmpeg_lite.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if __has_include("ffmpeg_lite.h")

typedef struct BridgeStringBuilder {
    char *data;
    size_t length;
    size_t capacity;
} BridgeStringBuilder;

#if DEBUG
static double bridge_now_milliseconds(void) {
    struct timespec time;
    clock_gettime(CLOCK_MONOTONIC, &time);
    return ((double) time.tv_sec * 1000.0) + ((double) time.tv_nsec / 1000000.0);
}

static void bridge_log(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    fprintf(stderr, "[SubtitleFFmpegBridge] ");
    vfprintf(stderr, format, arguments);
    fprintf(stderr, "\n");
    fflush(stderr);
    va_end(arguments);
}
#else
static double bridge_now_milliseconds(void) {
    return 0;
}

static void bridge_log(const char *format, ...) {
    (void) format;
}
#endif

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
    size_t header_length = headers ? strlen(headers) : 0;
    double started_at = bridge_now_milliseconds();
    bridge_log(
        "open_input start url=%s headerBytes=%zu",
        media_url ? media_url : "<null>",
        header_length
    );

    AVDictionary *options = NULL;
    if (headers && headers[0] != '\0') {
        av_dict_set(&options, "headers", headers, 0);
    }

    double open_started_at = bridge_now_milliseconds();
    int result = avformat_open_input(format_context, media_url, NULL, &options);
    double open_elapsed = bridge_now_milliseconds() - open_started_at;
    av_dict_free(&options);
    bridge_log(
        "open_input avformat_open_input result=%d elapsed=%.1fms",
        result,
        open_elapsed
    );
    if (result < 0 || !*format_context) {
        bridge_log("open_input failed while opening source");
        bridge_set_error(error_message, "打开媒体失败。");
        return -1;
    }

    double info_started_at = bridge_now_milliseconds();
    result = avformat_find_stream_info(*format_context, NULL);
    double info_elapsed = bridge_now_milliseconds() - info_started_at;
    bridge_log(
        "open_input avformat_find_stream_info result=%d elapsed=%.1fms streams=%u",
        result,
        info_elapsed,
        (*format_context)->nb_streams
    );
    if (result < 0) {
        bridge_set_error(error_message, "读取媒体流信息失败。");
        avformat_close_input(format_context);
        return -1;
    }

    bridge_log(
        "open_input ready totalElapsed=%.1fms",
        bridge_now_milliseconds() - started_at
    );
    return 0;
}

static char *bridge_dict_value(AVDictionary *dictionary, const char *key) {
    AVDictionaryEntry *entry = av_dict_get(dictionary, key, NULL, 0);
    return entry ? bridge_strdup(entry->value) : NULL;
}

static const char *bridge_dict_borrowed_value(AVDictionary *dictionary, const char *key) {
    AVDictionaryEntry *entry = av_dict_get(dictionary, key, NULL, 0);
    return entry ? entry->value : NULL;
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

static int64_t bridge_packet_base_milliseconds(
    int64_t subtitle_pts,
    int64_t packet_pts,
    AVRational time_base
) {
    int64_t base = bridge_pts_to_milliseconds(packet_pts, time_base);
    if (base < 0 && subtitle_pts != AV_NOPTS_VALUE) {
        base = subtitle_pts / 1000;
    }
    if (base < 0) {
        base = 0;
    }
    return base;
}

static void bridge_event_bounds_milliseconds(
    int64_t subtitle_pts,
    int64_t packet_pts,
    int64_t packet_duration,
    AVRational time_base,
    uint32_t start_display_time,
    uint32_t end_display_time,
    int *start_ms,
    int *end_ms
) {
    int64_t base = bridge_packet_base_milliseconds(subtitle_pts, packet_pts, time_base);
    int resolved_start_ms = (int) (base + start_display_time);
    int64_t packet_duration_ms = bridge_pts_to_milliseconds(packet_duration, time_base);
    int resolved_end_ms = 0;
    if (end_display_time > start_display_time) {
        resolved_end_ms = (int) (base + end_display_time);
    } else if (packet_duration_ms > 0) {
        resolved_end_ms = (int) (base + packet_duration_ms);
    } else {
        resolved_end_ms = resolved_start_ms + 1000;
    }

    if (start_ms) {
        *start_ms = resolved_start_ms;
    }
    if (end_ms) {
        *end_ms = resolved_end_ms;
    }
}

static bool bridge_ranges_overlap(
    int event_start_ms,
    int event_end_ms,
    int64_t window_start_ms,
    int64_t window_end_ms
) {
    return (int64_t) event_end_ms >= window_start_ms && (int64_t) event_start_ms <= window_end_ms;
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
    int64_t packet_duration,
    AVRational time_base,
    uint32_t start_display_time,
    uint32_t end_display_time
) {
    int64_t base = bridge_pts_to_milliseconds(packet_pts, time_base);
    if (base < 0 && subtitle_pts != AV_NOPTS_VALUE) {
        base = subtitle_pts / 1000;
    }
    if (base < 0) {
        base = 0;
    }

    int start_ms = (int) (base + start_display_time);
    int64_t packet_duration_ms = bridge_pts_to_milliseconds(packet_duration, time_base);
    int end_ms = 0;
    if (end_display_time > start_display_time) {
        end_ms = (int) (base + end_display_time);
    } else if (packet_duration_ms > 0) {
        end_ms = (int) (base + packet_duration_ms);
    } else {
        end_ms = start_ms + 1000;
    }

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

static int bridge_append_ass_event_dialogue(
    BridgeStringBuilder *builder,
    const char *ass_event,
    int64_t subtitle_pts,
    int64_t packet_pts,
    int64_t packet_duration,
    AVRational time_base,
    uint32_t start_display_time,
    uint32_t end_display_time
) {
    if (!ass_event || ass_event[0] == '\0') {
        return 0;
    }

    if (strncmp(ass_event, "Dialogue:", 9) == 0) {
        if (bridge_builder_append_string(builder, ass_event) < 0) {
            return -1;
        }
        return bridge_builder_append_string(builder, "\n");
    }

    int64_t base = bridge_pts_to_milliseconds(packet_pts, time_base);
    if (base < 0 && subtitle_pts != AV_NOPTS_VALUE) {
        base = subtitle_pts / 1000;
    }
    if (base < 0) {
        base = 0;
    }

    int start_ms = (int) (base + start_display_time);
    int64_t packet_duration_ms = bridge_pts_to_milliseconds(packet_duration, time_base);
    int end_ms = 0;
    if (end_display_time > start_display_time) {
        end_ms = (int) (base + end_display_time);
    } else if (packet_duration_ms > 0) {
        end_ms = (int) (base + packet_duration_ms);
    } else {
        end_ms = start_ms + 1000;
    }

    char start_buffer[32];
    char end_buffer[32];
    bridge_format_ass_time(start_ms, start_buffer, sizeof(start_buffer));
    bridge_format_ass_time(end_ms, end_buffer, sizeof(end_buffer));

    char *event_copy = bridge_strdup(ass_event);
    if (!event_copy) {
        return -1;
    }

    char *parts[9] = {0};
    parts[0] = event_copy;
    int part_count = 1;
    for (char *cursor = event_copy; *cursor && part_count < 9; cursor++) {
        if (*cursor == ',') {
            *cursor = '\0';
            parts[part_count++] = cursor + 1;
        }
    }

    int result = 0;
    if (part_count >= 9) {
        const char *layer = parts[1] && parts[1][0] ? parts[1] : "0";
        const char *style = parts[2] ? parts[2] : "Default";
        const char *name = parts[3] ? parts[3] : "";
        const char *margin_l = parts[4] ? parts[4] : "0";
        const char *margin_r = parts[5] ? parts[5] : "0";
        const char *margin_v = parts[6] ? parts[6] : "0";
        const char *effect = parts[7] ? parts[7] : "";
        const char *text = parts[8] ? parts[8] : "";

        result = bridge_builder_append_format(
            builder,
            "Dialogue: %s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n",
            layer,
            start_buffer,
            end_buffer,
            style,
            name,
            margin_l,
            margin_r,
            margin_v,
            effect,
            text
        );
    } else {
        result = bridge_builder_append_format(
            builder,
            "Dialogue: 0,%s,%s,Default,,0,0,0,,",
            start_buffer,
            end_buffer
        );
        if (result >= 0) {
            result = bridge_builder_append_string(builder, ass_event);
        }
        if (result >= 0) {
            result = bridge_builder_append_string(builder, "\n");
        }
    }

    free(event_copy);
    return result;
}

static int bridge_append_subtitle_rect(
    BridgeStringBuilder *ass_events,
    BridgeStringBuilder *text_events,
    AVSubtitleRect *rect,
    AVSubtitle subtitle,
    AVPacket *packet,
    AVRational time_base,
    int64_t window_start_ms,
    int64_t window_end_ms,
    bool apply_window_filter,
    bool *has_ass_events,
    bool *has_text_events,
    int *ass_rect_count,
    int *text_rect_count
) {
    if (!rect) {
        return 0;
    }

    int event_start_ms = 0;
    int event_end_ms = 0;
    bridge_event_bounds_milliseconds(
        subtitle.pts,
        packet->pts,
        packet->duration,
        time_base,
        subtitle.start_display_time,
        subtitle.end_display_time,
        &event_start_ms,
        &event_end_ms
    );

    if (apply_window_filter && !bridge_ranges_overlap(event_start_ms, event_end_ms, window_start_ms, window_end_ms)) {
        return 0;
    }

    if (rect->type == SUBTITLE_ASS && rect->ass && rect->ass[0] != '\0') {
        if (has_ass_events) {
            *has_ass_events = true;
        }
        if (ass_rect_count) {
            *ass_rect_count += 1;
        }
        return bridge_append_ass_event_dialogue(
            ass_events,
            rect->ass,
            subtitle.pts,
            packet->pts,
            packet->duration,
            time_base,
            subtitle.start_display_time,
            subtitle.end_display_time
        );
    }

    if (rect->text && rect->text[0] != '\0') {
        if (has_text_events) {
            *has_text_events = true;
        }
        if (text_rect_count) {
            *text_rect_count += 1;
        }
        return bridge_append_text_dialogue(
            text_events,
            rect->text,
            subtitle.pts,
            packet->pts,
            packet->duration,
            time_base,
            subtitle.start_display_time,
            subtitle.end_display_time
        );
    }

    return 0;
}

int subtitle_bridge_copy_tracks(
    const char *media_url,
    const char *headers,
    SubtitleBridgeTrackInfo **tracks,
    int *count,
    char **error_message
) {
    double started_at = bridge_now_milliseconds();
    *tracks = NULL;
    *count = 0;
    if (error_message) {
        *error_message = NULL;
    }
    bridge_log(
        "copy_tracks start url=%s",
        media_url ? media_url : "<null>"
    );

    AVFormatContext *format_context = NULL;
    if (bridge_open_input(media_url, headers, &format_context, error_message) < 0) {
        bridge_log("copy_tracks failed before stream scan");
        return -1;
    }
    unsigned int stream_count = format_context->nb_streams;

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
        bridge_log(
            "copy_tracks found stream=%d codec=%s language=%s title=%s",
            item->stream_index,
            item->codec_name ? item->codec_name : "<unknown>",
            item->language ? item->language : "<none>",
            item->title ? item->title : "<none>"
        );
    }

    avformat_close_input(&format_context);

    if (subtitle_count == 0) {
        free(items);
        bridge_log(
            "copy_tracks completed subtitleCount=0 totalStreams=%u elapsed=%.1fms",
            stream_count,
            bridge_now_milliseconds() - started_at
        );
        return 0;
    }

    *tracks = items;
    *count = subtitle_count;
    bridge_log(
        "copy_tracks completed subtitleCount=%d totalStreams=%u elapsed=%.1fms",
        subtitle_count,
        stream_count,
        bridge_now_milliseconds() - started_at
    );
    return 0;
}

int subtitle_bridge_copy_ass_document(
    const char *media_url,
    const char *headers,
    int stream_index,
    char **ass_document,
    char **error_message
) {
    double started_at = bridge_now_milliseconds();
    *ass_document = NULL;
    if (error_message) {
        *error_message = NULL;
    }
    bridge_log(
        "copy_ass_document start url=%s stream=%d headerBytes=%zu",
        media_url ? media_url : "<null>",
        stream_index,
        headers ? strlen(headers) : 0
    );

    AVFormatContext *format_context = NULL;
    if (bridge_open_input(media_url, headers, &format_context, error_message) < 0) {
        bridge_log("copy_ass_document failed before locating target stream");
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
        bridge_log("copy_ass_document target stream %d not found", stream_index);
        bridge_set_error(error_message, "找不到内嵌字幕轨。");
        return -1;
    }
    bridge_log(
        "copy_ass_document target stream located stream=%d codec=%s language=%s title=%s timebase=%d/%d",
        target_stream->index,
        avcodec_get_name(target_stream->codecpar->codec_id),
        bridge_dict_borrowed_value(target_stream->metadata, "language")
            ? bridge_dict_borrowed_value(target_stream->metadata, "language")
            : "<none>",
        bridge_dict_borrowed_value(target_stream->metadata, "title")
            ? bridge_dict_borrowed_value(target_stream->metadata, "title")
            : "<none>",
        target_stream->time_base.num,
        target_stream->time_base.den
    );

    const AVCodec *codec = avcodec_find_decoder(target_stream->codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&format_context);
        bridge_log(
            "copy_ass_document no decoder for codec=%s",
            avcodec_get_name(target_stream->codecpar->codec_id)
        );
        bridge_set_error(error_message, "找不到字幕解码器。");
        return -1;
    }

    AVCodecContext *codec_context = avcodec_alloc_context3(codec);
    if (!codec_context) {
        avformat_close_input(&format_context);
        bridge_log("copy_ass_document failed to allocate codec context");
        bridge_set_error(error_message, "分配字幕解码器失败。");
        return -1;
    }

    if (avcodec_parameters_to_context(codec_context, target_stream->codecpar) < 0 ||
        avcodec_open2(codec_context, codec, NULL) < 0) {
        bridge_log(
            "copy_ass_document failed to open decoder=%s",
            avcodec_get_name(target_stream->codecpar->codec_id)
        );
        avcodec_free_context(&codec_context);
        avformat_close_input(&format_context);
        bridge_set_error(error_message, "打开字幕解码器失败。");
        return -1;
    }
    bridge_log(
        "copy_ass_document decoder ready name=%s extradataBytes=%d",
        avcodec_get_name(target_stream->codecpar->codec_id),
        codec_context->extradata_size
    );

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
    int total_packets = 0;
    int subtitle_packets = 0;
    int decoded_subtitles = 0;
    int decode_failures = 0;
    int ass_rect_count = 0;
    int text_rect_count = 0;
    double packet_scan_started_at = bridge_now_milliseconds();
    bridge_log("copy_ass_document packet scan start stream=%d", stream_index);

    while (av_read_frame(format_context, packet) >= 0) {
        total_packets += 1;
        if (packet->stream_index != stream_index) {
            av_packet_unref(packet);
            continue;
        }
        subtitle_packets += 1;
        if (subtitle_packets == 1) {
            bridge_log(
                "copy_ass_document first subtitle packet pts=%lld duration=%lld size=%d",
                (long long) packet->pts,
                (long long) packet->duration,
                packet->size
            );
        }
        if ((subtitle_packets % 100) == 0) {
            bridge_log(
                "copy_ass_document progress totalPackets=%d subtitlePackets=%d decoded=%d assRects=%d textRects=%d failures=%d elapsed=%.1fms",
                total_packets,
                subtitle_packets,
                decoded_subtitles,
                ass_rect_count,
                text_rect_count,
                decode_failures,
                bridge_now_milliseconds() - packet_scan_started_at
            );
        }

        AVSubtitle subtitle = {0};
        int got_subtitle = 0;
        int decode_result = avcodec_decode_subtitle2(codec_context, &subtitle, &got_subtitle, packet);
        if (decode_result < 0) {
            decode_failures += 1;
            if (decode_failures <= 3 || (decode_failures % 25) == 0) {
                bridge_log(
                    "copy_ass_document decode failure code=%d packetPts=%lld packetDuration=%lld",
                    decode_result,
                    (long long) packet->pts,
                    (long long) packet->duration
                );
            }
        }
        if (decode_result >= 0 && got_subtitle) {
            decoded_subtitles += 1;
            for (unsigned int rect_index = 0; rect_index < subtitle.num_rects; rect_index++) {
                bridge_append_subtitle_rect(
                    &ass_events,
                    &text_events,
                    subtitle.rects[rect_index],
                    subtitle,
                    packet,
                    target_stream->time_base,
                    0,
                    0,
                    false,
                    &has_ass_events,
                    &has_text_events,
                    &ass_rect_count,
                    &text_rect_count
                );
            }
            avsubtitle_free(&subtitle);
        }

        av_packet_unref(packet);
    }

    av_packet_free(&packet);
    avcodec_free_context(&codec_context);
    avformat_close_input(&format_context);
    bridge_log(
        "copy_ass_document packet scan finished totalPackets=%d subtitlePackets=%d decoded=%d assRects=%d textRects=%d failures=%d elapsed=%.1fms",
        total_packets,
        subtitle_packets,
        decoded_subtitles,
        ass_rect_count,
        text_rect_count,
        decode_failures,
        bridge_now_milliseconds() - packet_scan_started_at
    );

    BridgeStringBuilder final_document = {0};
    if (has_ass_events) {
        if (ass_header.length == 0) {
            bridge_builder_append_string(&ass_header, bridge_default_ass_header);
        }
        bridge_builder_append_string(&final_document, ass_header.data);
        bridge_builder_append_string(&final_document, ass_events.data);
        bridge_log(
            "copy_ass_document assembled ASS document bytes=%zu totalElapsed=%.1fms",
            final_document.length,
            bridge_now_milliseconds() - started_at
        );
    } else if (has_text_events) {
        bridge_builder_append_string(&final_document, bridge_default_ass_header);
        bridge_builder_append_string(&final_document, text_events.data);
        bridge_log(
            "copy_ass_document assembled text ASS document bytes=%zu totalElapsed=%.1fms",
            final_document.length,
            bridge_now_milliseconds() - started_at
        );
    } else {
        bridge_builder_free(&ass_header);
        bridge_builder_free(&ass_events);
        bridge_builder_free(&text_events);
        bridge_log(
            "copy_ass_document produced no renderable events totalElapsed=%.1fms",
            bridge_now_milliseconds() - started_at
        );
        bridge_set_error(error_message, "当前内嵌字幕轨暂不支持自渲染。");
        return -1;
    }

    bridge_builder_free(&ass_header);
    bridge_builder_free(&ass_events);
    bridge_builder_free(&text_events);

    *ass_document = final_document.data;
    return 0;
}

int subtitle_bridge_copy_ass_document_window(
    const char *media_url,
    const char *headers,
    int stream_index,
    int64_t window_start_ms,
    int64_t window_end_ms,
    char **ass_document,
    char **error_message
) {
    double started_at = bridge_now_milliseconds();
    *ass_document = NULL;
    if (error_message) {
        *error_message = NULL;
    }

    if (window_end_ms < window_start_ms) {
        bridge_set_error(error_message, "无效的字幕时间窗口。");
        return -1;
    }

    bridge_log(
        "copy_ass_document_window start url=%s stream=%d window=[%lld,%lld]",
        media_url ? media_url : "<null>",
        stream_index,
        (long long) window_start_ms,
        (long long) window_end_ms
    );

    AVFormatContext *format_context = NULL;
    if (bridge_open_input(media_url, headers, &format_context, error_message) < 0) {
        bridge_log("copy_ass_document_window failed before locating target stream");
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
        bridge_log("copy_ass_document_window target stream %d not found", stream_index);
        bridge_set_error(error_message, "找不到内嵌字幕轨。");
        return -1;
    }

    const AVCodec *codec = avcodec_find_decoder(target_stream->codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&format_context);
        bridge_log(
            "copy_ass_document_window no decoder for codec=%s",
            avcodec_get_name(target_stream->codecpar->codec_id)
        );
        bridge_set_error(error_message, "找不到字幕解码器。");
        return -1;
    }

    AVCodecContext *codec_context = avcodec_alloc_context3(codec);
    if (!codec_context) {
        avformat_close_input(&format_context);
        bridge_log("copy_ass_document_window failed to allocate codec context");
        bridge_set_error(error_message, "分配字幕解码器失败。");
        return -1;
    }

    if (avcodec_parameters_to_context(codec_context, target_stream->codecpar) < 0 ||
        avcodec_open2(codec_context, codec, NULL) < 0) {
        bridge_log(
            "copy_ass_document_window failed to open decoder=%s",
            avcodec_get_name(target_stream->codecpar->codec_id)
        );
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

    int64_t seek_target_ms = window_start_ms > 15000 ? window_start_ms - 15000 : 0;
    if (target_stream->time_base.num > 0 && target_stream->time_base.den > 0) {
        int64_t seek_timestamp = (seek_target_ms * (int64_t) target_stream->time_base.den)
            / ((int64_t) target_stream->time_base.num * 1000);
        int seek_result = av_seek_frame(format_context, stream_index, seek_timestamp, AVSEEK_FLAG_BACKWARD);
        bridge_log(
            "copy_ass_document_window seek result=%d targetMs=%lld timestamp=%lld",
            seek_result,
            (long long) seek_target_ms,
            (long long) seek_timestamp
        );
        if (seek_result >= 0) {
            avcodec_flush_buffers(codec_context);
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
    int ass_rect_count = 0;
    int text_rect_count = 0;
    int subtitle_packets = 0;
    int matched_rect_count = 0;
    const int64_t stop_after_ms = window_end_ms + 15000;

    while (av_read_frame(format_context, packet) >= 0) {
        if (packet->stream_index != stream_index) {
            av_packet_unref(packet);
            continue;
        }

        subtitle_packets += 1;
        int64_t packet_ms = bridge_packet_base_milliseconds(AV_NOPTS_VALUE, packet->pts, target_stream->time_base);
        if (subtitle_packets > 1 && packet_ms > stop_after_ms) {
            av_packet_unref(packet);
            break;
        }

        AVSubtitle subtitle = {0};
        int got_subtitle = 0;
        int decode_result = avcodec_decode_subtitle2(codec_context, &subtitle, &got_subtitle, packet);
        if (decode_result >= 0 && got_subtitle) {
            for (unsigned int rect_index = 0; rect_index < subtitle.num_rects; rect_index++) {
                int ass_before = ass_rect_count;
                int text_before = text_rect_count;
                bridge_append_subtitle_rect(
                    &ass_events,
                    &text_events,
                    subtitle.rects[rect_index],
                    subtitle,
                    packet,
                    target_stream->time_base,
                    window_start_ms,
                    window_end_ms,
                    true,
                    &has_ass_events,
                    &has_text_events,
                    &ass_rect_count,
                    &text_rect_count
                );
                matched_rect_count += (ass_rect_count - ass_before) + (text_rect_count - text_before);
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
        if (ass_header.length == 0) {
            bridge_builder_append_string(&ass_header, bridge_default_ass_header);
        }
        bridge_builder_append_string(&final_document, ass_header.data);
    }

    bridge_builder_free(&ass_header);
    bridge_builder_free(&ass_events);
    bridge_builder_free(&text_events);

    bridge_log(
        "copy_ass_document_window finished subtitlePackets=%d matchedRects=%d bytes=%zu elapsed=%.1fms",
        subtitle_packets,
        matched_rect_count,
        final_document.length,
        bridge_now_milliseconds() - started_at
    );

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

int subtitle_bridge_copy_ass_document_window(
    const char *media_url,
    const char *headers,
    int stream_index,
    int64_t window_start_ms,
    int64_t window_end_ms,
    char **ass_document,
    char **error_message
) {
    (void) media_url;
    (void) headers;
    (void) stream_index;
    (void) window_start_ms;
    (void) window_end_ms;
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
