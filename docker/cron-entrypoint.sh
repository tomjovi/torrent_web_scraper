#!/bin/bash
set -euo pipefail

CRON_SCHEDULE="${CRON_SCHEDULE:-0 */3 * * *}"
LOG_FILE="${SCRAPER_LOG_FILE:-/scraper/config/scraper-cron.log}"

cat > /usr/local/bin/run-scraper.sh <<SCRIPT
#!/bin/bash
set -euo pipefail
cd /scraper
exec /usr/local/bin/python3 __main__.py --password "${TRANSMISSION_PASSWORD:-}"
SCRIPT
chmod +x /usr/local/bin/run-scraper.sh

cat > /etc/cron.d/scraper <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
${CRON_SCHEDULE} root /usr/local/bin/run-scraper.sh >> ${LOG_FILE} 2>&1
EOF
chmod 0644 /etc/cron.d/scraper

echo "스크래퍼 cron 등록: ${CRON_SCHEDULE}"
echo "로그 파일: ${LOG_FILE}"
exec cron -f
