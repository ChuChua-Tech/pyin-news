"""Local inference must never follow a redirect or inherit a web proxy."""

import io
import json
import os
import unittest
from unittest import mock

from test_ranking import load_backend

backend = load_backend()
http = backend.news_http


class Response(io.BytesIO):
    def __init__(self, data=b'{}', status=200, headers=None):
        super().__init__(data)
        self.status = status
        self.headers = headers or {'Content-Type':'application/json'}

    def getheader(self, name):
        return self.headers.get(name)


class LocalHTTPTests(unittest.TestCase):
    def setUp(self):
        self.socket = mock.Mock()
        self.socket.getpeername.return_value = ('127.0.0.1',9000)
        self.socket.fileno.return_value = 77
        self.control = mock.Mock()
        self.connection = mock.Mock()
        self.response = Response()
        self.connection.getresponse.return_value = self.response
        for owner, name, options in (
            (http.socket,'socket',{'side_effect':[self.socket,self.control]}),
            (http.os,'dup',{'return_value':88}),
            (http.http.client,'HTTPConnection',{'return_value':self.connection}),
            (http.socket,'getaddrinfo',{'side_effect':AssertionError('Local AI must not resolve DNS')}),
        ):
            patcher = mock.patch.object(owner,name,**options)
            patcher.start(); self.addCleanup(patcher.stop)

    def test_loopback_uses_numeric_connect_and_ignores_proxy_environment(self):
        with mock.patch.dict(os.environ, {'HTTP_PROXY':'http://unwanted','HTTPS_PROXY':'http://unwanted'}):
            with http.local_post('http://localhost:9000/v1/chat/completions',b'{}') as response:
                self.assertEqual(response.read(100),b'{}')
        self.socket.connect.assert_called_once_with(('127.0.0.1',9000))
        self.assertEqual(self.connection.auto_open,0)
        self.assertEqual(self.connection.request.call_args.args,('POST','/v1/chat/completions'))
        self.assertTrue(self.response.closed)
        self.control.close.assert_called_once()

    def test_redirect_is_rejected_without_a_second_request(self):
        self.connection.getresponse.return_value = Response(status=307,headers={'Location':'https://outside.example'})
        with self.assertRaisesRegex(RuntimeError,'redirects'):
            with http.local_post('http://127.0.0.1:9000/v1/chat/completions',b'{}'):
                self.fail('Redirect was accepted')
        self.assertEqual(self.connection.request.call_count,1)

    def test_peer_mismatch_fails_before_sending_article(self):
        self.socket.getpeername.return_value = ('10.0.0.1',9000)
        with self.assertRaisesRegex(ValueError,'unexpected peer'):
            with http.local_post('http://127.0.0.1:9000/',b'Article'):
                self.fail('Unexpected peer accepted')
        self.connection.request.assert_not_called()

    def test_invalid_urls_and_credentials_are_rejected_before_connect(self):
        for url in ('http://example.com','http://127.1/','http://2130706433/',
                    'http://user:secret@localhost/','http://localhost:0/',
                    'http://localhost/\nheader','http://localhost\\evil/',
                    'http://[::ffff:127.0.0.1]/','file:///etc/passwd'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                http.local_url(url)
        self.socket.connect.assert_not_called()

    def test_reply_size_and_stream_event_limits(self):
        self.connection.getresponse.return_value = Response(b'x'*65)
        with http.local_post('http://localhost:9000/',b'{}',max_bytes=64) as response:
            with self.assertRaisesRegex(ValueError,'size limit'):
                response.read(64)

    def test_stream_lines_are_reassembled_across_network_chunks(self):
        response = Response(b'data: {"text":"first"}\n\ndata: [DONE]\n')
        chunks = iter([b'data: {"te',b'xt":"first"}\n\nda',b'ta: [DONE]\n',b''])
        response.read1 = lambda size:next(chunks)
        reader = http.LocalResponse(response, float('inf'),1000)
        self.assertEqual(list(reader),[b'data: {"text":"first"}',b'',b'data: [DONE]'])

    def test_response_tool_calls_are_errors_for_stream_and_full_json(self):
        for value in ({'choices':[{'delta':{'tool_calls':[{'function':{'name':'read_file'}}]}}]},
                      {'choices':[{'message':{'content':'text','function_call':{'name':'shell'}}}]},
                      {'message':{'tool_calls':[{}]}}):
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError,'tool call'):
                backend._stream_content(value)


if __name__ == '__main__':
    unittest.main()
