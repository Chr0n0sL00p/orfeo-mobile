# Orfeo Mobile · Rust Core iOS Engine

Cliente móvil de alta fidelidad para iPhone 16 Pro desarrollado desde cero con motor en **Rust** (`orfeo-core`) e interfaz fluida en ProMotion 120 Hz.

## 🚀 Características Principales

1. **Control Continuo de Google Nest Mini (Comedor):**
   - Transmisión Bit-Perfect directa al puerto `4550` de Odiseo.
   - Panel inferior deslizante estilo Spotify Connect / AirPlay (sin ventanas de alerta intrusivas).
   - Control de volumen continuo (slider 0-100%) con retroalimentación instantánea y micro-ajustes (`+/- 5%`).
2. **Gapless Playback Predictivo:**
   - Pre-descarga de 2 MB del siguiente tema en memoria RAM 15 segundos antes de terminar la pista actual. Transición instantánea de 0 ms.
3. **Entrega de Carátulas en WebP:**
   - Carga de miniaturas a ~14 KB por carátula, acelerando el scroll 10 veces en pantallas Super Retina.
4. **Streaming Adaptativo Inteligente:**
   - FLAC Lossless Bit-Perfect en red local / Wi-Fi.
   - Transcodificación al vuelo a Opus 160 kbps en 5G fuera de casa (ahorro del 80% en datos).
5. **Dynamic Island & Background Playback:**
   - Integración con AVAudioSession para reproducción continua con pantalla bloqueada.
   - Control nativo desde la pantalla de bloqueo y Dynamic Island.

## 🔄 Actualización Inalámbrica (Sin Cables)

Para actualizar Orfeo en tu iPhone sin conectar cables:
- **SideStore:** Añade el repositorio `orfeo-apps.json` a tus fuentes en SideStore. Cada compilación de GitHub Actions actualizará la app de forma autónoma por Wi-Fi o datos móviles.
- **Safari OTA:** Abre `manifest.plist` con Safari sobre la red privada de Tailscale para instalar en 1 toque.
