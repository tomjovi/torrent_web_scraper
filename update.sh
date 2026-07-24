#!/usr/bin/env bash
set -euo pipefail

# torrent_web_scraper 소스를 git 동기화하고 manager 컨테이너를 재기동합니다.
#
# 사용법:
#   cd /volume1/docker/torrent_web_scraper
#   ./update.sh
#
# 환경변수:
#   BRANCH          동기화할 브랜치 (기본: master)
#   REMOTE          git remote 이름 (기본: origin)
#   COMPOSE_DIR     docker-compose.yml 경로 (기본: /volume1/docker/torrentscraper)
#   IMAGE_TAG       Docker 이미지 태그 (기본: torrentscraper-custom:latest)
#   CONTAINER_NAME  manager 컨테이너 이름 (기본: torrentscraper-manager)
#   FORCE_REBUILD   1이면 항상 이미지 재빌드
#   SKIP_TEST       1이면 재기동 후 접속 테스트 생략
#   USE_SUDO        1이면 docker 명령에 sudo 사용 (기본: 1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BRANCH="${BRANCH:-master}"
REMOTE="${REMOTE:-origin}"
COMPOSE_DIR="${COMPOSE_DIR:-/volume1/docker/torrentscraper}"
IMAGE_TAG="${IMAGE_TAG:-torrentscraper-custom:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-torrentscraper-manager}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
SKIP_TEST="${SKIP_TEST:-0}"
USE_SUDO="${USE_SUDO:-1}"

run() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

container_exists() {
  run docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"
}

echo "==> git 동기화 (${REMOTE}/${BRANCH})"
PREV_HEAD="$(git rev-parse HEAD)"
git fetch "$REMOTE" "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only "$REMOTE" "$BRANCH"

REBUILD=0
if [ "$FORCE_REBUILD" = "1" ]; then
  REBUILD=1
elif git diff --name-only "$PREV_HEAD" HEAD | grep -qE '^(requirements\.txt|docker/Dockerfile)$'; then
  REBUILD=1
fi

if [ "$REBUILD" = "1" ]; then
  echo "==> Docker 이미지 재빌드: ${IMAGE_TAG}"
  run docker build -f docker/Dockerfile -t "$IMAGE_TAG" .
else
  echo "==> Docker 이미지 재빌드 생략 (Python 소스만 변경됨)"
fi

if [ -f "${COMPOSE_DIR}/docker-compose.yml" ]; then
  echo "==> manager 재기동 (${COMPOSE_DIR})"
  (cd "$COMPOSE_DIR" && run docker compose up -d --force-recreate manager)
elif container_exists; then
  echo "==> 컨테이너 재시작 (${CONTAINER_NAME})"
  run docker restart "$CONTAINER_NAME"
else
  echo "경고: ${COMPOSE_DIR}/docker-compose.yml 과 ${CONTAINER_NAME} 컨테이너를 찾지 못했습니다."
  echo "COMPOSE_DIR 또는 CONTAINER_NAME 환경변수를 확인하세요."
  exit 1
fi

if [ "$SKIP_TEST" = "1" ]; then
  echo "완료 (테스트 생략)"
  exit 0
fi

if container_exists; then
  echo "==> 접속 테스트"
  if run docker exec "$CONTAINER_NAME" python3 /scraper/scraperHelpers.py \
    "https://torrentzota194.com/t/2.html" --savePath /tmp/test.html; then
    echo "완료"
  else
    echo "테스트 실패. 로그 확인:"
    echo "  sudo docker exec ${CONTAINER_NAME} tail -50 /scraper/config/scraper.log"
    exit 1
  fi
else
  echo "완료"
fi
