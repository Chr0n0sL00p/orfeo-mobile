#!/usr/bin/env bash
set -e

# Orfeo Mobile · OTA Deployment Script to Odiseo
ODISEO_HOST="100.117.169.38"
ODISEO_USER="snow"
REMOTE_DIR="/opt/jarvis/music_app/static/mobile"

echo ">>> [Orfeo OTA] Preparando despliegue Over-The-Air a Odiseo..."

BUILD_NUM=$(date +%s)
VERSION="2.4.1"
DATE_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
CHANGELOG="Corrección de audio en iPhone: transcodificación AAC 320k de alta fidelidad, eliminación de bloqueos de sesión de audio y carga segura de streams"

# Comprobar si se ejecuta localmente en Odiseo
if [ -d "$REMOTE_DIR" ] && (ip -4 addr show 2>/dev/null | grep -q "${ODISEO_HOST}" || [ "$(hostname)" = "Odiseo" ]); then
  echo ">>> [Orfeo OTA] Modo local en servidor Odiseo detectado."
  cp frontend/index.html "${REMOTE_DIR}/index.html"
  cat << EOF > "${REMOTE_DIR}/version.json"
{
  "version": "${VERSION}",
  "build": ${BUILD_NUM},
  "release_date": "${DATE_ISO}",
  "changelog": "${CHANGELOG}",
  "bundle_url": "/static/mobile/index.html"
}
EOF
else
  echo ">>> [Orfeo OTA] Modo remoto detectado, enviando vía SCP/SSH..."
  scp frontend/index.html ${ODISEO_USER}@${ODISEO_HOST}:${REMOTE_DIR}/index.html
  ssh ${ODISEO_USER}@${ODISEO_HOST} "cat << 'EOF' > ${REMOTE_DIR}/version.json
{
  \"version\": \"${VERSION}\",
  \"build\": ${BUILD_NUM},
  \"release_date\": \"${DATE_ISO}\",
  \"changelog\": \"${CHANGELOG}\",
  \"bundle_url\": \"/static/mobile/index.html\"
}
EOF"
fi

echo ">>> [Orfeo OTA] ¡Despliegue completado! Build: ${BUILD_NUM}"
echo ">>> Al abrir Orfeo en tu iPhone 16 Pro, la app detectará la actualización y la aplicará al instante sin cables."

