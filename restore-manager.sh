#!/usr/bin/env bash
set -euo pipefail

# 기존 /volume1/docker/torrentscraper (istandthon7/torrentscraper manager) 복구용입니다.
# torrent_web_scraper 의 새 scraper 서비스와는 별개입니다.
#
# 사용법:
#   cd /volume1/docker/torrent_web_scraper
#   ./restore-manager.sh
#
# 환경변수:
#   COMPOSE_DIR     docker-compose.yml 경로 (기본: /volume1/docker/torrentscraper)
#   USE_SUDO        1이면 docker 명령에 sudo 사용 (기본: 1)

COMPOSE_DIR="${COMPOSE_DIR:-/volume1/docker/torrentscraper}"
COMPOSE_FILE="${COMPOSE_FILE:-${COMPOSE_DIR}/docker-compose.yml}"
USE_SUDO="${USE_SUDO:-1}"

run() {
  if [ "$USE_SUDO" = "1" ]; then
    sudo "$@"
  else
    "$@"
  fi
}

if [ ! -f "$COMPOSE_FILE" ]; then
  echo "오류: ${COMPOSE_FILE} 을 찾을 수 없습니다."
  exit 1
fi

echo "==> 중복 manager 컨테이너 정리"
mapfile -t MANAGER_CONTAINERS < <(run docker ps -a --format '{{.Names}}' | grep 'torrentscraper-manager' || true)
for name in "${MANAGER_CONTAINERS[@]}"; do
  echo "  stop/remove: ${name}"
  run docker stop "$name" 2>/dev/null || true
  run docker rm "$name" 2>/dev/null || true
done

BACKUP_FILE="${COMPOSE_FILE}.bak.$(date +%Y%m%d%H%M%S)"
cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "==> compose 백업: ${BACKUP_FILE}"

python3 - "$COMPOSE_FILE" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

text = re.sub(
    r'^\s*-\s*/volume1/docker/torrent_web_scraper:/scraper\s*\n',
    '',
    text,
    flags=re.MULTILINE,
)
text = text.replace('torrentscraper-custom:latest', 'istandthon7/torrentscraper:latest')

path.write_text(text, encoding="utf-8")
print(f"==> compose 복구 완료: {path}")
PY

echo "==> 공식 이미지 pull"
run docker pull istandthon7/torrentscraper:latest

echo "==> manager 재기동"
(cd "$COMPOSE_DIR" && run docker compose up -d manager)

ACTIVE_CONTAINER="$(run docker ps --format '{{.Names}}' | grep 'torrentscraper-manager' | head -n 1 || true)"
if [ -n "$ACTIVE_CONTAINER" ]; then
  echo "==> 컨테이너 상태"
  run docker ps --filter "name=${ACTIVE_CONTAINER}"
  echo
  echo "웹 UI가 정상인지 확인하세요. 이후 curl_cffi 적용은 docker-compose.source.example.yml 을 참고해 단계적으로 진행하세요."
else
  echo "경고: manager 컨테이너가 실행되지 않았습니다."
  echo "  sudo docker compose -f ${COMPOSE_FILE} logs manager --tail 100"
  exit 1
fi
