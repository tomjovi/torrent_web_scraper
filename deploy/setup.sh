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

if [ -d "${REPO_DIR}/src" ]; then
  if [ "${REPO_DIR}" != "${SOURCE_DIR}" ] && [ ! -d "${SOURCE_DIR}/src" ]; then
    echo "오류: SOURCE_DIR 에 src/ 가 없습니다: ${SOURCE_DIR}"
    echo "소스를 먼저 옮기세요:"
    echo "  mkdir -p /volume1/dev"
    echo "  mv /volume1/docker/torrent_web_scraper /volume1/dev/torrent_web_scraper"
    exit 1
  fi
  if [ ! -d "${SOURCE_DIR}/src" ]; then
    SOURCE_DIR="${REPO_DIR}"
  fi
else
  echo "오류: 이 스크립트는 git 저장소 루트에서 실행하세요."
  exit 1
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
else
  sed -i "s|^SOURCE_DIR=.*|SOURCE_DIR=${SOURCE_DIR}|" "${DEPLOY_DIR}/.env"
fi

CONFIG_VOLUME="$(grep '^CONFIG_VOLUME=' "${DEPLOY_DIR}/.env" | cut -d= -f2- || true)"
if [ -z "${CONFIG_VOLUME}" ]; then
  CONFIG_VOLUME="torrent_web_scraper_config"
fi

if ! run docker volume inspect "${CONFIG_VOLUME}" >/dev/null 2>&1; then
  echo "==> config volume 생성: ${CONFIG_VOLUME}"
  run docker volume create "${CONFIG_VOLUME}"
fi

LEGACY_NETWORK="$(grep '^LEGACY_DOCKER_NETWORK=' "${DEPLOY_DIR}/.env" | cut -d= -f2- || true)"
if [ -z "${LEGACY_NETWORK}" ]; then
  LEGACY_NETWORK="torrentscraper_default"
fi

echo ""
echo "==> 사전 확인"
if run docker network inspect "${LEGACY_NETWORK}" >/dev/null 2>&1; then
  echo "  [OK] 기존 compose 네트워크: ${LEGACY_NETWORK}"
  echo "       setting.json → torrentClient.host = transmission 권장"
else
  echo "  [주의] 네트워크를 찾지 못했습니다: ${LEGACY_NETWORK}"
  echo "         docker network ls | grep torrentscraper 로 이름 확인"
  echo "         또는 setting.json → torrentClient.host = host.docker.internal (호스트 9091 포트)"
fi

if echo "${CONFIG_VOLUME}" | grep -q 'torrent_manager'; then
  echo "  [주의] 기존 manager config 볼륨을 공유합니다."
  echo "         /volume1/docker/torrentscraper manager 스케줄/사이트를 비활성화하세요."
fi

if [ -d "${DEPLOY_DIR}/.git" ] 2>/dev/null || [ -d "${DEPLOY_DIR}/src" ]; then
  echo "  [주의] ${DEPLOY_DIR} 에 git 소스가 남아 있습니다."
  echo "         배포 폴더에는 compose/.env 만 두고 소스는 ${SOURCE_DIR} 로 옮기세요."
fi

cat <<EOF

==> 배포 파일 준비 완료
  소스:   ${SOURCE_DIR}
  배포:   ${DEPLOY_DIR}

다음 단계:
  1) ${DEPLOY_DIR}/.env 에서 TRANSMISSION_PASSWORD, CONFIG_VOLUME, LEGACY_DOCKER_NETWORK 확인
  2) config 의 setting.json 에서 torrentClient.host 를 transmission 또는 host.docker.internal 로 변경
  3) cd ${SOURCE_DIR} && ./update.sh

EOF
