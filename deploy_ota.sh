#!/usr/bin/env bash
set -e

# Orfeo Mobile · OTA Deployment Script to Odiseo
ODISEO_HOST="100.117.169.38"
ODISEO_USER="snow"
REMOTE_DIR="/opt/jarvis/music_app/static/mobile"

echo ">>> [Orfeo OTA] Preparando despliegue Over-The-Air a Odiseo..."

# 1. Copiar index.html al servidor Odiseo
scp frontend/index.html ${ODISEO_USER}@${ODISEO_HOST}:${REMOTE_DIR}/index.html

# 2. Generar version.json con nuevo timestamp y build
BUILD_NUM=$(date +%s)
VERSION="2.0.1"
DATE_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

ssh ${ODISEO_USER}@${ODISEO_HOST} "cat << 'EOF' > ${REMOTE_DIR}/version.json
{
  \"version\": \"${VERSION}\",
  \"build\": ${BUILD_NUM},
  \"release_date\": \"${DATE_ISO}\",
  \"changelog\": \"Actualización OTA automática desde PC Ryzen\",
  \"bundle_url\": \"/static/mobile/index.html\"
}
EOF"

echo ">>> [Orfeo OTA] ¡Despliegue completado! Build: ${BUILD_NUM}"
echo ">>> Al abrir Orfeo en tu iPhone 16 Pro, la app detectará la actualización y la aplicará al instante sin cables."
