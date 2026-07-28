#!/usr/bin/env bash
set -euo pipefail

# 소스(git) 동기화 후 배포 compose 로 scraper 컨테이너를 업데이트합니다.
#
# 사용법:
#   cd /volume1/dev/torrent_web_scraper
#   ./update.sh
#
# 환경변수:
#   SOURCE_DIR      git 소스 경로 (기본: 이 스크립트가 있는 디렉터리)
#   DEPLOY_DIR      compose/.env 위치 (기본: /volume1/docker/torrent_web_scraper)
#   BRANCH          동기화할 브랜치 (기본: master)
#   REMOTE          git remote 이름 (기본: origin)
#   FORCE_REBUILD   1이면 항상 이미지 재빌드
#   SKIP_TEST       1이면 접속 테스트 생략
#   USE_SUDO        1이면 docker 명령에 sudo 사용 (기본: 1)

SOURCE_DIR="${SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
DEPLOY_DIR="${DEPLOY_DIR:-/volume1/docker/torrent_web_scraper}"
COMPOSE_FILE="${DEPLOY_DIR}/docker-compose.yaml"
ENV_FILE="${DEPLOY_DIR}/.env"
BRANCH="${BRANCH:-master}"
REMOTE="${REMOTE:-origin}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
SKIP_TEST="${SKIP_TEST:-0}"
USE_SUDO="${USE_SUDO:-1}"
CONTAINER_NAME="${CONTAINER_NAME:-torrent-web-scraper}"

run() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

if [ ! -d "${SOURCE_DIR}/src" ]; then
  echo "오류: 소스 경로를 찾을 수 없습니다: ${SOURCE_DIR}/src"
  exit 1
fi

if [ ! -f "${COMPOSE_FILE}" ] || [ ! -f "${ENV_FILE}" ]; then
  echo "오류: 배포 파일이 없습니다."
  echo "  먼저 실행: cd ${SOURCE_DIR} && ./deploy/setup.sh"
  exit 1
fi

cd "${SOURCE_DIR}"

echo "==> git 동기화 (${REMOTE}/${BRANCH})"
PREV_HEAD="$(git rev-parse HEAD)"
git fetch "$REMOTE" "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only "$REMOTE" "$BRANCH"

REBUILD=0
if [ "$FORCE_REBUILD" = "1" ]; then
  REBUILD=1
elif git diff --name-only "$PREV_HEAD" HEAD | grep -qE '^(src/requirements\.txt|docker/Dockerfile|docker/cron-entrypoint\.sh|deploy/docker-compose\.yaml)$'; then
  REBUILD=1
fi

cd "${DEPLOY_DIR}"

if [ "$REBUILD" = "1" ]; then
  echo "==> Docker 이미지 빌드"
  run docker compose build
else
  echo "==> Docker 이미지 빌드 생략 (src 소스만 변경됨, bind mount로 즉시 반영)"
fi

echo "==> scraper 컨테이너 재기동"
if [ "$REBUILD" = "1" ]; then
  run docker compose up -d
elif ! run docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  run docker compose up -d
else
  echo "==> 실행 중인 컨테이너 유지 (재기동 생략)"
fi

if [ "$SKIP_TEST" = "1" ]; then
  echo "완료 (테스트 생략)"
  exit 0
fi

if ! run docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "오류: ${CONTAINER_NAME} 컨테이너가 실행 중이 아닙니다."
  echo "  sudo docker compose -f ${COMPOSE_FILE} logs scraper --tail 100"
  exit 1
fi

echo "==> Python 스크래퍼 접속 테스트"
if run docker exec "$CONTAINER_NAME" python3 /scraper/scraperHelpers.py \
  "https://torrentzota194.com/t/2.html" --savePath /tmp/test.html; then
  echo "완료"
else
  echo "테스트 실패:"
  echo "  sudo docker compose -f ${COMPOSE_FILE} logs scraper --tail 100"
  echo "  sudo docker exec ${CONTAINER_NAME} tail -50 /scraper/config/scraper.log"
  exit 1
fi
