#ifndef SubtitleFFmpegBridge_h
#define SubtitleFFmpegBridge_h

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SubtitleBridgeTrackInfo {
    int stream_index;
    char *language;
    char *title;
    char *codec_name;
} SubtitleBridgeTrackInfo;

int subtitle_bridge_copy_tracks(
    const char *media_url,
    const char *headers,
    SubtitleBridgeTrackInfo **tracks,
    int *count,
    char **error_message
);

int subtitle_bridge_copy_ass_document(
    const char *media_url,
    const char *headers,
    int stream_index,
    char **ass_document,
    char **error_message
);

void subtitle_bridge_free_tracks(SubtitleBridgeTrackInfo *tracks, int count);
void subtitle_bridge_free_string(char *string);

#ifdef __cplusplus
}
#endif

#endif
