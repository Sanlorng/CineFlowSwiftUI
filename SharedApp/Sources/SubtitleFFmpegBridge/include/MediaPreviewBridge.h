#ifndef MEDIA_PREVIEW_BRIDGE_H
#define MEDIA_PREVIEW_BRIDGE_H
#include <stdint.h>
typedef struct MediaPreviewRequest MediaPreviewRequest;
typedef struct { double time; char *title; } MediaPreviewChapter;
typedef struct { uint8_t *pixels; int width; int height; double time; } MediaPreviewFrame;
MediaPreviewRequest *media_preview_request_create(void);
void media_preview_request_cancel(MediaPreviewRequest *request);
void media_preview_request_free(MediaPreviewRequest *request);
int media_preview_chapters(MediaPreviewRequest *request, const char *url, const char *headers, int bypass_proxy, MediaPreviewChapter **chapters, int *count);
void media_preview_chapters_free(MediaPreviewChapter *chapters, int count);
int media_preview_frame(MediaPreviewRequest *request, const char *url, const char *headers, int bypass_proxy, double time, MediaPreviewFrame *frame);
void media_preview_frame_free(MediaPreviewFrame *frame);
#endif
