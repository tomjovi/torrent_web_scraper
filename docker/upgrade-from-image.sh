#!/bin/bash
set -euo pipefail

# NAS에서 수정된 스크래퍼 소스 기반으로 manager 이미지를 빌드하고 재기동합니다.
#
# 사용법:
#   cd /volume1/docker/torrentscraper
#   SCRAPER_SOURCE=/volume1/docker/torrent_web_scraper ./upgrade-from-image.sh
#
# 환경변수:
#   SCRAPER_SOURCE  clone 받은 torrent_web_scraper 경로 (기본: ../torrent_web_scraper)
#   COMPOSE_DIR     docker-compose.yml 이 있는 경로 (기본: 현재 디렉터리)
#   IMAGE_TAG       빌드할 이미지 태그 (기본: torrentscraper-custom:latest)

SCRAPER_SOURCE="${SCRAPER_SOURCE:-../torrent_web_scraper}"
COMPOSE_DIR="${COMPOSE_DIR:-.}"
IMAGE_TAG="${IMAGE_TAG:-torrentscraper-custom:latest}"

if [ ! -f "${SCRAPER_SOURCE}/docker/Dockerfile" ]; then
  echo "오류: ${SCRAPER_SOURCE}/docker/Dockerfile 을 찾을 수 없습니다."
  echo "먼저 저장소를 clone 하세요:"
  echo "  git clone https://github.com/tomjovi/torrent_web_scraper.git ${SCRAPER_SOURCE}"
  exit 1
fi

echo "==> 이미지 빌드: ${IMAGE_TAG}"
sudo docker build -f "${SCRAPER_SOURCE}/docker/Dockerfile" -t "${IMAGE_TAG}" "${SCRAPER_SOURCE}"

if [ ! -f "${COMPOSE_DIR}/docker-compose.yml" ]; then
  echo "경고: ${COMPOSE_DIR}/docker-compose.yml 을 찾지 못했습니다."
  echo "docker-compose.yml 의 manager 서비스를 수동으로 수정하세요."
  echo "예시: docker/docker-compose.source.example.yml 참고"
  exit 0
fi

echo "==> compose 재기동"
cd "${COMPOSE_DIR}"
sudo docker compose pull transmission 2>/dev/null || true
sudo docker compose up -d --force-recreate manager

echo "==> 동작 확인"
sudo docker exec torrentscraper-manager python3 /scraper/scraperHelpers.py \
  "https://torrentzota194.com/t/2.html" --savePath /tmp/test.html

echo "완료. 실패 시 로그 확인:"
echo "  sudo docker exec torrentscraper-manager tail -50 /scraper/config/scraper.log"
