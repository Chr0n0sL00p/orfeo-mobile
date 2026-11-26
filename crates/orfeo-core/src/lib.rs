use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::{Arc, Mutex, OnceLock};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NestCastState {
    pub is_casting: bool,
    pub device_name: String,
    pub volume: f32, // 0.0 to 1.0
    pub state: String, // "IDLE", "PLAYING", "PAUSED"
    pub cast_server_url: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EngineStatus {
    pub is_initialized: bool,
    pub server_url: String,
    pub current_track_id: Option<String>,
    pub next_preloaded_id: Option<String>,
    pub preloaded_bytes: usize,
    pub is_gapless_ready: bool,
    pub network_profile: String, // "wifi_flac" or "cellular_opus"
    pub memory_usage_kb: usize,
    pub nest_cast: NestCastState,
}

pub struct OrfeoCoreEngine {
    pub server_url: String,
    pub current_track: Option<String>,
    pub preloaded_track: Option<String>,
    pub preloaded_buffer: Vec<u8>,
    pub network_profile: String,
    pub nest_cast: NestCastState,
}

impl OrfeoCoreEngine {
    pub fn new() -> Self {
        Self {
            server_url: "http://100.117.169.38:4538".to_string(), // Default Odiseo Tailscale
            current_track: None,
            preloaded_track: None,
            preloaded_buffer: Vec::new(),
            network_profile: "wifi_flac".to_string(),
            nest_cast: NestCastState {
                is_casting: false,
                device_name: "Google Nest Mini (Comedor)".to_string(),
                volume: 0.55,
                state: "IDLE".to_string(),
                cast_server_url: "http://100.117.169.38:4550".to_string(),
            },
        }
    }

    pub fn set_server(&mut self, url: String) {
        self.server_url = url;
    }

    pub fn set_network_profile(&mut self, profile: String) {
        self.network_profile = profile;
    }

    pub fn play(&mut self, track_id: String) {
        self.current_track = Some(track_id.clone());
        if self.preloaded_track.as_deref() == Some(&track_id) {
            self.preloaded_track = None;
            self.preloaded_buffer.clear();
        }
    }

    pub fn preload_next(&mut self, track_id: String) {
        self.preloaded_track = Some(track_id);
        self.preloaded_buffer = vec![0u8; 2 * 1024 * 1024]; // 2 MB pre-buffer
    }

    // Google Nest Mini Controls
    pub fn set_cast_state(&mut self, is_casting: bool) {
        self.nest_cast.is_casting = is_casting;
        self.nest_cast.state = if is_casting { "PLAYING".to_string() } else { "IDLE".to_string() };
    }

    pub fn set_cast_volume(&mut self, vol: f32) {
        self.nest_cast.volume = vol.clamp(0.0, 1.0);
    }

    pub fn get_status(&self) -> EngineStatus {
        EngineStatus {
            is_initialized: true,
            server_url: self.server_url.clone(),
            current_track_id: self.current_track.clone(),
            next_preloaded_id: self.preloaded_track.clone(),
            preloaded_bytes: self.preloaded_buffer.len(),
            is_gapless_ready: !self.preloaded_buffer.is_empty(),
            network_profile: self.network_profile.clone(),
            memory_usage_kb: 22_400,
            nest_cast: self.nest_cast.clone(),
        }
    }
}

static ENGINE: OnceLock<Arc<Mutex<OrfeoCoreEngine>>> = OnceLock::new();

fn get_engine() -> &'static Arc<Mutex<OrfeoCoreEngine>> {
    ENGINE.get_or_init(|| Arc::new(Mutex::new(OrfeoCoreEngine::new())))
}

// -------------------------------------------------------------
// C-FFI Interface for iOS Swift / Objective-C Integration
// -------------------------------------------------------------

#[no_mangle]
pub extern "C" fn orfeo_engine_init() -> bool {
    let _ = get_engine();
    true
}

#[no_mangle]
pub extern "C" fn orfeo_engine_set_server(server_url: *const c_char) -> bool {
    if server_url.is_null() { return false; }
    let c_str = unsafe { CStr::from_ptr(server_url) };
    if let Ok(url) = c_str.to_str() {
        if let Ok(mut engine) = get_engine().lock() {
            engine.set_server(url.to_string());
            return true;
        }
    }
    false
}

#[no_mangle]
pub extern "C" fn orfeo_engine_set_network_mode(mode: *const c_char) -> bool {
    if mode.is_null() { return false; }
    let c_str = unsafe { CStr::from_ptr(mode) };
    if let Ok(m) = c_str.to_str() {
        if let Ok(mut engine) = get_engine().lock() {
            engine.set_network_profile(m.to_string());
            return true;
        }
    }
    false
}

#[no_mangle]
pub extern "C" fn orfeo_engine_play_track(track_id: *const c_char) -> bool {
    if track_id.is_null() { return false; }
    let c_str = unsafe { CStr::from_ptr(track_id) };
    if let Ok(id) = c_str.to_str() {
        if let Ok(mut engine) = get_engine().lock() {
            engine.play(id.to_string());
            return true;
        }
    }
    false
}

#[no_mangle]
pub extern "C" fn orfeo_engine_preload_next(track_id: *const c_char) -> bool {
    if track_id.is_null() { return false; }
    let c_str = unsafe { CStr::from_ptr(track_id) };
    if let Ok(id) = c_str.to_str() {
        if let Ok(mut engine) = get_engine().lock() {
            engine.preload_next(id.to_string());
            return true;
        }
    }
    false
}

// Google Nest Mini C-FFI Controls
#[no_mangle]
pub extern "C" fn orfeo_engine_nest_connect() -> bool {
    if let Ok(mut engine) = get_engine().lock() {
        engine.set_cast_state(true);
        return true;
    }
    false
}

#[no_mangle]
pub extern "C" fn orfeo_engine_nest_disconnect() -> bool {
    if let Ok(mut engine) = get_engine().lock() {
        engine.set_cast_state(false);
        return true;
    }
    false
}

#[no_mangle]
pub extern "C" fn orfeo_engine_nest_set_volume(volume: f32) -> bool {
    if let Ok(mut engine) = get_engine().lock() {
        engine.set_cast_volume(volume);
        return true;
    }
    false
}

#[no_mangle]
pub extern "C" fn orfeo_engine_get_status() -> *mut c_char {
    let status = match get_engine().lock() {
        Ok(engine) => engine.get_status(),
        Err(_) => EngineStatus {
            is_initialized: false,
            server_url: String::new(),
            current_track_id: None,
            next_preloaded_id: None,
            preloaded_bytes: 0,
            is_gapless_ready: false,
            network_profile: "unknown".to_string(),
            memory_usage_kb: 0,
            nest_cast: NestCastState {
                is_casting: false,
                device_name: "Google Nest Mini".to_string(),
                volume: 0.5,
                state: "IDLE".to_string(),
                cast_server_url: String::new(),
            },
        },
    };

    let json = serde_json::to_string(&status).unwrap_or_else(|_| "{}".to_string());
    CString::new(json).map(|cs| cs.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn orfeo_engine_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}
