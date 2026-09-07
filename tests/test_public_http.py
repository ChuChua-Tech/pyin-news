"""Exercise the public web connection boundary, including redirects and peers."""
import io
import socket
import ssl
import unittest
from unittest import mock
from test_ranking import load_backend

http = load_backend().news_http
PUBLIC = '93.184.216.34'


def answer(address=PUBLIC, port=443):
    family = socket.AF_INET6 if ':' in address else socket.AF_INET
    return (family, socket.SOCK_STREAM, 6, '', (address, port))


class Response(io.BytesIO):
    def __init__(self, body=b'ok', status=200, headers=None):
        super().__init__(body)
        self.status, self.headers, self.reason = status, headers or {}, 'fixture'

    def getheader(self, key):
        return self.headers.get(key)


class PublicWebTests(unittest.TestCase):
    def setUp(self):
        self.sock = mock.Mock()
        self.sock.getpeername.return_value = (PUBLIC, 443)
        self.conn = mock.Mock()
        self.conn.getresponse.return_value = Response()
        self.context = mock.Mock()
        self.context.wrap_socket.return_value = self.sock
        for target, name, options in (
            (http.socket, 'getaddrinfo', {'return_value': [answer()]}),
            (http.socket, 'socket', {'return_value': self.sock}),
            (http.http.client, 'HTTPConnection', {'return_value': self.conn}),
            (http.ssl, 'create_default_context', {'return_value': self.context}),
        ):
            patcher = mock.patch.object(target, name, **options)
            setattr(self, name, patcher.start())
            self.addCleanup(patcher.stop)

    def test_literal_and_url_policy(self):
        for url in ('file:///etc/passwd', 'ftp://example.com/a', 'http://localhost/',
                    'https://foo.localhost./', 'https://u:p@example.com', 'https://@example.com',
                    'https://example.com:8080', 'https://example.com/\nfoo', 'https://example.com\\@evil.com',
                    'http://[fe80::1%25eth0]/'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                http.get(url, 32)
        self.socket.assert_not_called()

    def test_nonpublic_and_transition_addresses_rejected_before_socket(self):
        for address in ('127.0.0.1', '10.0.0.1', '172.16.1.1', '192.168.1.1',
                        '169.254.169.254', '100.64.0.1', '0.0.0.0', '224.0.0.1',
                        '240.0.0.1', '192.0.2.1', '::', '::1', 'fc00::1', 'fe80::1',
                        'ff02::1', '2001:db8::1', '::ffff:8.8.8.8', '2002:0808:0808::1',
                        '64:ff9b::808:808'):
            with self.subTest(address=address):
                self.getaddrinfo.return_value = [answer(address)]
                with self.assertRaises(ValueError):
                    http.get('https://example.com/', 32)
                self.socket.assert_not_called()

    def test_mixed_dns_answers_and_numeric_alias_fail_closed(self):
        self.getaddrinfo.return_value = [answer(), answer('127.0.0.1')]
        with self.assertRaises(ValueError):
            http.get('https://example.com/', 32)
        self.getaddrinfo.return_value = [answer('127.0.0.1')]
        with self.assertRaises(ValueError):
            http.get('http://2130706433/', 32)
        self.socket.assert_not_called()

    def test_connect_uses_validated_ip_with_original_host_and_tls_name(self):
        data, _, status = http.get('https://example.com/story?q=1#fragment', 32,
                                  headers={'Authorization': 'secret', 'Cookie': 'secret', 'User-Agent': 'PYIN'})
        self.assertEqual((data, status), (b'ok', 200))
        self.getaddrinfo.assert_called_once_with('example.com', 443, type=socket.SOCK_STREAM)
        self.sock.connect.assert_called_once_with((PUBLIC, 443))
        self.context.wrap_socket.assert_called_once_with(self.sock, server_hostname='example.com')
        self.assertEqual(self.conn.auto_open, 0)
        args = self.conn.request.call_args
        self.assertEqual(args.args, ('GET', '/story?q=1'))
        self.assertEqual(args.kwargs['headers']['Host'], 'example.com')
        self.assertNotIn('Authorization', args.kwargs['headers'])
        self.assertNotIn('Cookie', args.kwargs['headers'])
        self.sock.close.assert_called()
        self.assertTrue(self.conn.getresponse.return_value.closed)

    def test_peer_mismatch_rejected_before_tls_or_http(self):
        for peer in ('127.0.0.1', '8.8.8.8'):
            self.sock.getpeername.return_value = (peer, 443)
            with self.assertRaises(ValueError):
                http.get('https://example.com/', 32)
        self.context.wrap_socket.assert_not_called()
        self.conn.request.assert_not_called()

    def test_tls_peer_is_rechecked(self):
        self.sock.getpeername.side_effect = [(PUBLIC, 443), ('127.0.0.1', 443)]
        with self.assertRaises(ValueError):
            http.get('https://example.com/', 32)
        self.conn.request.assert_not_called()

    def test_redirect_to_private_target_is_blocked(self):
        for location in ('http://127.0.0.1/admin', 'http://[::1]/', 'http://user:pass@example.com/', '/bad\npath'):
            self.conn.request.reset_mock()
            self.conn.getresponse.return_value = Response(status=302, headers={'Location': location})
            with self.assertRaises(ValueError):
                http.get('https://example.com/', 32)
            self.assertEqual(self.conn.request.call_count, 1)

    def test_same_host_redirect_rechecks_dns(self):
        self.conn.getresponse.return_value = Response(status=302, headers={'Location': '/second'})
        self.getaddrinfo.side_effect = [[answer()], [answer('10.0.0.1')]]
        with self.assertRaises(ValueError):
            http.get('https://example.com/', 32)
        self.assertEqual(self.conn.request.call_count, 1)
        self.assertEqual(self.socket.call_count, 1)

    def test_public_relative_redirect_and_conditional_not_modified(self):
        self.conn.getresponse.side_effect = [Response(status=302, headers={'Location': '../next'}),
                                             Response(status=304, headers={'ETag': 'tag'})]
        data, headers, status = http.get('https://example.com/path/start', 32, headers={'If-None-Match': 'tag'})
        self.assertEqual((data, status, headers['ETag']), (b'', 304, 'tag'))
        self.assertEqual(self.getaddrinfo.call_count, 2)
        self.assertEqual(self.conn.request.call_args.args, ('GET', '/next'))

    def test_redirect_limit(self):
        self.conn.getresponse.return_value = Response(status=302, headers={'Location': '/again'})
        with self.assertRaises(ValueError):
            http.get('https://example.com/', 32)
        self.assertEqual(self.conn.request.call_count, 6)

    def test_content_length_and_stream_limits(self):
        for response in (Response(headers={'Content-Length': '33'}),
                         Response(headers={'Content-Length': '-1'}), Response(b'x' * 33)):
            self.conn.getresponse.return_value = response
            with self.assertRaises(ValueError):
                http.get('https://example.com/', 32)
        self.conn.getresponse.return_value = Response(b'x' * 32)
        self.assertEqual(len(http.get('https://example.com/', 32)[0]), 32)

    def test_connection_close_response_owns_socket_during_body_read(self):
        def response():
            self.sock.settimeout.side_effect = OSError('closed socket handle')
            return Response(b'publisher body')
        self.conn.getresponse.side_effect = response
        self.assertEqual(http.get('https://example.com/', 32)[0], b'publisher body')

    def test_connection_failure_can_try_another_validated_public_ip(self):
        self.getaddrinfo.return_value = [answer(), answer('8.8.8.8')]
        self.sock.connect.side_effect = [OSError('unreachable'), None]
        self.sock.getpeername.return_value = ('8.8.8.8', 443)
        self.assertEqual(http.get('https://example.com/', 32)[0], b'ok')
        self.assertEqual(self.sock.connect.call_args.args, (('8.8.8.8', 443),))

    def test_backend_preserves_conditional_validators(self):
        backend = load_backend()
        self.conn.getresponse.return_value = Response(status=304, headers={'ETag': 'new'})
        body, validators = backend.http_get_conditional('https://example.com/rss', 32, etag='old', last_modified='yesterday')
        self.assertIsNone(body)
        self.assertEqual(validators, {'etag': 'new', 'last_modified': 'yesterday'})


if __name__ == '__main__':
    unittest.main()
