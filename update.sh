#!/usr/bin/env bash
set -euo pipefail

# torrent_web_scraper 소스를 git 동기화하고 필요할 때만 manager를 재기동합니다.
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
#   FORCE_RESTART   1이면 변경 없어도 컨테이너 재생성
#   SKIP_TEST       1이면 재기동 후 접속 테스트 생략
#   USE_SUDO        1이면 docker 명령에 sudo 사용 (기본: 1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BRANCH="${BRANCH:-master}"
REMOTE="${REMOTE:-origin}"
COMPOSE_DIR="${COMPOSE_DIR:-/volume1/docker/torrentscraper}"
COMPOSE_FILE="${COMPOSE_FILE:-${COMPOSE_DIR}/docker-compose.yml}"
IMAGE_TAG="${IMAGE_TAG:-torrentscraper-custom:latest}"
CONTAINER_NAME="${CONTAINER_NAME:-torrentscraper-manager}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
FORCE_RESTART="${FORCE_RESTART:-0}"
SKIP_TEST="${SKIP_TEST:-0}"
USE_SUDO="${USE_SUDO:-1}"

run() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

image_exists() {
  run docker image inspect "$IMAGE_TAG" >/dev/null 2>&1
}

compose_uses_custom_image() {
  [ -f "$COMPOSE_FILE" ] && grep -q "$IMAGE_TAG" "$COMPOSE_FILE"
}

compose_has_source_mount() {
  [ -f "$COMPOSE_FILE" ] && grep -q "${SCRIPT_DIR}:/scraper" "$COMPOSE_FILE"
}

find_manager_container() {
  if run docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "$CONTAINER_NAME"
    return 0
  fi
  run docker ps -a --format '{{.Names}}' | grep -E 'torrentscraper-manager' | head -n 1
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
elif compose_uses_custom_image && ! image_exists; then
  echo "==> 커스텀 이미지가 없어 최초 빌드를 진행합니다."
  REBUILD=1
fi

if [ "$REBUILD" = "1" ]; then
  echo "==> Docker 이미지 빌드: ${IMAGE_TAG}"
  run docker build -f docker/Dockerfile -t "$IMAGE_TAG" .
else
  echo "==> Docker 이미지 빌드 생략"
fi

RESTART=0
if [ "$FORCE_RESTART" = "1" ] || [ "$REBUILD" = "1" ]; then
  RESTART=1
elif compose_has_source_mount; then
  echo "==> 소스 bind mount 사용 중: 컨테이너 재기동 생략 (파일 변경은 즉시 반영됨)"
else
  if ! git diff --quiet "$PREV_HEAD" HEAD; then
    RESTART=1
  fi
fi

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "오류: ${COMPOSE_FILE} 을 찾을 수 없습니다."
  exit 1
fi

if [ "$RESTART" = "1" ]; then
  echo "==> manager 재기동 (${COMPOSE_DIR})"
  (cd "$COMPOSE_DIR" && run docker compose up -d manager)
else
  echo "==> manager 재기동 생략"
fi

ACTIVE_CONTAINER="$(find_manager_container || true)"
if [ -n "$ACTIVE_CONTAINER" ] && [ "$ACTIVE_CONTAINER" != "$CONTAINER_NAME" ]; then
  echo "경고: 예상 컨테이너명(${CONTAINER_NAME})과 다릅니다: ${ACTIVE_CONTAINER}"
  echo "docker-compose.yml 에 container_name: torrentscraper-manager 가 있는지 확인하세요."
fi

DUPLICATE_COUNT="$(run docker ps -a --format '{{.Names}}' | grep -c 'torrentscraper-manager' || true)"
if [ "${DUPLICATE_COUNT:-0}" -gt 1 ]; then
  echo "경고: manager 컨테이너가 ${DUPLICATE_COUNT}개 있습니다. 502 원인이 될 수 있습니다."
  echo "  sudo docker ps -a | grep manager"
  echo "  중복 컨테이너를 정리한 뒤 다시 실행하세요."
fi

if [ "$SKIP_TEST" = "1" ]; then
  echo "완료 (테스트 생략)"
  exit 0
fi

if [ -z "$ACTIVE_CONTAINER" ]; then
  echo "완료 (실행 중인 manager 컨테이너 없음)"
  exit 0
fi

echo "==> Python 스크래퍼 접속 테스트 (${ACTIVE_CONTAINER})"
if run docker exec "$ACTIVE_CONTAINER" python3 /scraper/scraperHelpers.py \
  "https://torrentzota194.com/t/2.html" --savePath /tmp/test.html; then
  echo "완료"
else
  echo "스크래퍼 테스트 실패. manager 웹 UI와는 별개일 수 있습니다."
  echo "  sudo docker logs ${ACTIVE_CONTAINER} --tail 100"
  echo "  sudo docker exec ${ACTIVE_CONTAINER} tail -50 /scraper/config/scraper.log"
  exit 1
fi
