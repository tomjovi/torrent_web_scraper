#!/usr/bin/env bash
set -euo pipefail

# 최초 1회: 배포 디렉터리(/volume1/docker/torrent_web_scraper)에 compose 파일을 준비합니다.
#
# 사용법:
#   cd /volume1/dev/torrent_web_scraper
#   ./deploy/setup.sh

SOURCE_DIR="${SOURCE_DIR:-/volume1/dev/torrent_web_scraper}"
DEPLOY_DIR="${DEPLOY_DIR:-/volume1/docker/torrent_web_scraper}"
USE_SUDO="${USE_SUDO:-1}"

run() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ "${REPO_DIR}" != "${SOURCE_DIR}" ] && [ -d "${SOURCE_DIR}/src" ]; then
  echo "소스 경로: ${SOURCE_DIR}"
else
  SOURCE_DIR="${REPO_DIR}"
fi

mkdir -p "${DEPLOY_DIR}"

if [ -f "${DEPLOY_DIR}/docker-compose.yaml" ]; then
  BACKUP="${DEPLOY_DIR}/docker-compose.yaml.bak.$(date +%Y%m%d%H%M%S)"
  cp "${DEPLOY_DIR}/docker-compose.yaml" "${BACKUP}"
  echo "기존 compose 백업: ${BACKUP}"
fi

cp "${SCRIPT_DIR}/docker-compose.yaml" "${DEPLOY_DIR}/docker-compose.yaml"

if [ ! -f "${DEPLOY_DIR}/.env" ]; then
  cp "${SCRIPT_DIR}/.env.example" "${DEPLOY_DIR}/.env"
  echo ".env 생성: ${DEPLOY_DIR}/.env"
else
  echo ".env 유지: ${DEPLOY_DIR}/.env"
fi

if ! grep -q '^SOURCE_DIR=' "${DEPLOY_DIR}/.env"; then
  echo "SOURCE_DIR=${SOURCE_DIR}" >> "${DEPLOY_DIR}/.env"
fi

CONFIG_VOLUME="$(grep '^CONFIG_VOLUME=' "${DEPLOY_DIR}/.env" | cut -d= -f2- || true)"
if [ -z "${CONFIG_VOLUME}" ]; then
  CONFIG_VOLUME="torrent_web_scraper_config"
fi

if ! run docker volume inspect "${CONFIG_VOLUME}" >/dev/null 2>&1; then
  echo "==> config volume 생성: ${CONFIG_VOLUME}"
  run docker volume create "${CONFIG_VOLUME}"
fi

cat <<EOF

==> 배포 파일 준비 완료
  소스:   ${SOURCE_DIR}
  배포:   ${DEPLOY_DIR}

다음 단계:
  1) ${DEPLOY_DIR}/.env 에서 TRANSMISSION_PASSWORD, CONFIG_VOLUME, 경로 확인
  2) CONFIG_VOLUME 을 기존 manager 와 공유할 경우, manager 스크랩을 비활성화하세요
  3) cd ${SOURCE_DIR} && ./update.sh

EOF
