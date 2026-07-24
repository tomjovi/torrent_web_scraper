import argparse
import logging
import random
import ssl
import sys
import time
from http.client import HTTPResponse
from typing import Optional, Protocol, Union
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

import setting

# 로그파일 초기화용
mySetting = setting.Setting()

# bs4 모듈이 설치되어 있는지 확인
try:
    from bs4 import BeautifulSoup
except ImportError:
    message = "Error: 'beautifulsoup4' 모듈이 설치되지 않았습니다."
    logging.error(message)
    sys.stderr.write(message)
    sys.exit(1)


class FetchResponse(Protocol):
    url: str

    def read(self) -> bytes:
        ...


class _BytesResponse:
    def __init__(self, content: bytes, url: str):
        self._content = content
        self.url = url

    def read(self) -> bytes:
        return self._content


def getSoup(url: str):
    try:
        html = getHtml(url)
        soup = BeautifulSoup(html, "html.parser")
        return soup
    except Exception as e:
        logging.error(f"Exception getSoup url: {url} , error: {str(e)}")
    return None


def getHtml(url: str):
    try:
        time.sleep(random.randrange(1, 4))
        response = getResponse(url)
        if response is not None:
            return response.read().decode('utf-8', 'replace')
    except Exception as e:
        logging.error("Exception getHtml url: "+url+" , error: " + str(e))
    return None


def _getResponseWithCurlCffi(url: str) -> Optional[_BytesResponse]:
    try:
        from curl_cffi import requests as curl_requests
    except ImportError:
        logging.debug("curl_cffi가 설치되어 있지 않아 urllib로 요청합니다.")
        return None

    try:
        response = curl_requests.get(
            url,
            impersonate="chrome120",
            timeout=30,
            verify=False,
        )
        if response.status_code > 400:
            logging.error(
                "일시적 접속실패이거나 사이트가 정상적으로 작동하지 않거나 "
                f"사이트보안이 강화되었거나 url이 잘못되었습니다. 에러코드: {response.status_code}, url: {url}"
            )
            return None
        logging.debug(f"curl_cffi로 HTML을 가져왔습니다. url: {url}")
        return _BytesResponse(response.content, str(response.url))
    except Exception as e:
        logging.error(f"curl_cffi 요청 중 오류가 발생했어요. 원인: {e}, url: {url}")
        return None


def _getResponseWithUrllib(url: str) -> Optional[HTTPResponse]:
    try:
        request = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        context = ssl._create_unverified_context()
        return urlopen(request, context=context)
    except HTTPError as er:
        if er.code > 400:
            logging.error(
                "일시적 접속실패이거나 사이트가 정상적으로 작동하지 않거나 "
                f"사이트보안이 강화되었거나 url이 잘못되었습니다. 에러코드: {er.code}, url: {url}"
            )
        else:
            raise
    except URLError as er:
        logging.error(f"URL을 열거나 읽는 동안 발생하는 오류가 발생했어요. 원인: {er.reason}, url: {url}")
    except ConnectionResetError as er:
        logging.error(f"네트워크 연결이 원격 호스트에 의해 강제로 재설정되었어요. 원인: {er.strerror}, url: {url}")
    return None


def getResponse(url: str) -> Optional[Union[HTTPResponse, _BytesResponse]]:
    response = _getResponseWithCurlCffi(url)
    if response is not None:
        return response
    return _getResponseWithUrllib(url)


def getSoupFromFile(filePath: str):
    try:
        soup = BeautifulSoup(open(filePath), "html.parser")
        return soup
    except Exception as e:
        logging.error("Exception getSoupFromFile path: "+filePath+" , error: " + str(e))


def getMainUrl(url: str, responseUrl: str) -> str:
    if responseUrl != url:
        parsedUrl = urlparse(responseUrl)
        mainDomain = f"https://{parsedUrl.netloc}/"
        if mainDomain != url:
            logging.info(f'url이 변경되었네요. [{url}]->[{mainDomain}]')
        return mainDomain
    return url


if __name__ == '__main__':
    logging.info("스크랩을 시작하는 중...")
    parser = argparse.ArgumentParser()
    parser.add_argument("url", help="저장할 url")
    parser.add_argument("--savePath", help="HTML을 저장할 경로")
    args = parser.parse_args()

    logging.info("HTML을 가져오는 중...")
    html = getHtml(args.url)
    if html is not None:
        with open(args.savePath, 'w', encoding='utf-8') as f:
            f.write(html)
    else:
        message = f"HTML을 가져오는 데 실패했습니다: {args.url}"
        logging.error(message)
        sys.stderr.write(message)
