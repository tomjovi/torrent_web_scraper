FROM istandthon7/torrentscraper:latest

COPY requirements.txt /tmp/scraper-requirements.txt
RUN pip install --no-cache-dir -r /tmp/scraper-requirements.txt \
    && rm /tmp/scraper-requirements.txt
