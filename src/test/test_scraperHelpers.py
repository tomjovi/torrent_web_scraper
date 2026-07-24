import unittest
from unittest.mock import MagicMock, patch

import scraperHelpers


class ScraperHelpersTest(unittest.TestCase):
    def test_getSoup(self):
        self.assertIsNotNone(scraperHelpers.getSoup("http://naver.com"))

    def test_getSoup_https(self):
        self.assertIsNotNone(scraperHelpers.getSoup("https://daum.net"))

    @patch("scraperHelpers._getResponseWithCurlCffi")
    def test_getResponse_prefers_curl_cffi(self, mock_curl):
        mock_curl.return_value = scraperHelpers._BytesResponse(b"<html></html>", "https://example.com/")
        response = scraperHelpers.getResponse("https://example.com/")
        self.assertIsNotNone(response)
        self.assertEqual(response.read(), b"<html></html>")
        mock_curl.assert_called_once_with("https://example.com/")

    def test_getMainUrl(self):
        mainUrl = "https://www.domain1.com/"
        responseUrl = "https://www.domain2.com/"
        self.assertEqual(responseUrl, scraperHelpers.getMainUrl(mainUrl, responseUrl))

    def test_getMainUrl2(self):
        mainUrl = "https://www.domain1.com/"
        responseUrl = "https://www.domain2.com/"
        self.assertEqual(responseUrl, scraperHelpers.getMainUrl(mainUrl, responseUrl+"home.php"))

    def test_getMainUrl3(self):
        mainUrl = "https://www.domain1.com/"
        responseUrl = "https://www.domain2.com/"
        self.assertEqual(responseUrl, scraperHelpers.getMainUrl(mainUrl, responseUrl+"kr/home.php"))

    def test_getMainUrlHttps(self):
        mainUrl = "https://www.domain1.com/"
        responseUrl = "http://www.domain2.com/"
        self.assertEqual("https://www.domain2.com/", scraperHelpers.getMainUrl(mainUrl, responseUrl))


if __name__ == '__main__':  
    unittest.main()