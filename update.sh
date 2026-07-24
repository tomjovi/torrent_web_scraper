#!/usr/bin/env bash
set -euo pipefail

# torrent_web_scraper git 동기화 및 scraper 컨테이너 업데이트
#
# 사용법:
#   cd /volume1/docker/torrent_web_scraper
#   ./update.sh
#
# 환경변수:
#   BRANCH          동기화할 브랜치 (기본: master)
#   REMOTE          git remote 이름 (기본: origin)
#   FORCE_REBUILD   1이면 항상 이미지 재빌드
#   SKIP_TEST       1이면 재기동 후 접속 테스트 생략
#   USE_SUDO        1이면 docker 명령에 sudo 사용 (기본: 1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

if [ ! -f ".env" ]; then
  echo "오류: .env 파일이 없습니다."
  echo "  cp .env.example .env"
  echo "  후 TRANSMISSION_PASSWORD, CONFIG_VOLUME 등을 설정하세요."
  exit 1
fi

echo "==> git 동기화 (${REMOTE}/${BRANCH})"
PREV_HEAD="$(git rev-parse HEAD)"
git fetch "$REMOTE" "$BRANCH"
git checkout "$BRANCH"
git pull --ff-only "$REMOTE" "$BRANCH"

REBUILD=0
if [ "$FORCE_REBUILD" = "1" ]; then
  REBUILD=1
elif git diff --name-only "$PREV_HEAD" HEAD | grep -qE '^(src/requirements\.txt|docker/Dockerfile|docker/cron-entrypoint\.sh|docker-compose\.yaml)$'; then
  REBUILD=1
fi

if [ "$REBUILD" = "1" ]; then
  echo "==> Docker 이미지 빌드"
  run docker compose build
else
  echo "==> Docker 이미지 빌드 생략 (src 소스만 변경됨, bind mount로 즉시 반영)"
fi

echo "==> scraper 컨테이너 재기동"
if [ "$REBUILD" = "1" ]; then
  run docker compose up -d
else
  # 소스만 변경된 경우 cron 프로세스는 계속 실행, 파일은 bind mount로 반영됨
  if ! run docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    run docker compose up -d
  else
    echo "==> 실행 중인 컨테이너 유지 (재기동 생략)"
  fi
fi

if [ "$SKIP_TEST" = "1" ]; then
  echo "완료 (테스트 생략)"
  exit 0
fi

if ! run docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "오류: ${CONTAINER_NAME} 컨테이너가 실행 중이 아닙니다."
  echo "  sudo docker compose logs scraper --tail 100"
  exit 1
fi

echo "==> Python 스크래퍼 접속 테스트"
if run docker exec "$CONTAINER_NAME" python3 /scraper/scraperHelpers.py \
  "https://torrentzota194.com/t/2.html" --savePath /tmp/test.html; then
  echo "완료"
else
  echo "테스트 실패:"
  echo "  sudo docker compose logs scraper --tail 100"
  echo "  sudo docker exec ${CONTAINER_NAME} tail -50 /scraper/config/scraper.log"
  exit 1
fi
