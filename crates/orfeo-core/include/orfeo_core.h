#ifndef ORFEO_CORE_H
#define ORFEO_CORE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

bool orfeo_engine_init(void);
bool orfeo_engine_set_server(const char* server_url);
bool orfeo_engine_set_network_mode(const char* mode);
bool orfeo_engine_play_track(const char* track_id);
bool orfeo_engine_preload_next(const char* track_id);

// Google Nest Mini Controls
bool orfeo_engine_nest_connect(void);
bool orfeo_engine_nest_disconnect(void);
bool orfeo_engine_nest_set_volume(float volume);

char* orfeo_engine_get_status(void);
void orfeo_engine_free_string(char* ptr);

#ifdef __cplusplus
}
#endif

#endif /* ORFEO_CORE_H */
