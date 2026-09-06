"""Images are optional, feed supplied, bounded and independent of reading state."""
import json
import os
from pathlib import Path
import struct
import tempfile
import time
import unittest
from unittest import mock
import xml.etree.ElementTree as ET
from test_ranking import load_backend, isolate_backend, NOW


def png(width=100, height=80):
    # Enough header data for the pre-decode size guard; native tests use a real PNG.
    return b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\rIHDR' + struct.pack('>II', width, height) + b'\0' * 16


class ArticleImageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.backend = load_backend(); isolate_backend(self.backend, self.tmp.name)
        self.images = self.backend.news_images
        self.cache = Path(self.tmp.name) / 'cache'
        self.backend.save_setup_profile(json.dumps(self.backend.default_setup_profile()))

    def test_preference_default_legacy_and_portability(self):
        self.assertIs(self.backend.load_setup_profile()['appearance']['article_images'], False)
        legacy = self.backend.default_setup_profile(); legacy['version'] = 9
        del legacy['appearance']['article_images']
        self.backend.validate_imported_profile(legacy)
        self.assertIs(self.backend.normalize_setup_profile(legacy)['appearance']['article_images'], False)
        self.backend.set_article_images(True)
        path = Path(self.tmp.name) / 'profile.json'
        self.backend.export_setup_profile(str(path)); self.backend.set_article_images(False)
        self.backend.import_setup_profile(str(path))
        self.assertIs(self.backend.load_setup_profile()['appearance']['article_images'], True)
        invalid = self.backend.load_setup_profile(); invalid['appearance']['article_images'] = 'false'
        path.write_text(json.dumps(invalid))
        with self.assertRaises(ValueError): self.backend.import_setup_profile(str(path))
        self.assertIs(self.backend.load_setup_profile()['appearance']['article_images'], True)

    def test_feed_images_prioritize_thumbnails_preserve_signatures_and_skip_tracking(self):
        xml = '''<rss xmlns:media="http://search.yahoo.com/mrss/"><channel><item>
        <title>Story</title><link>https://example.com/news/story</link>
        <description><![CDATA[<img src="/pixel.png" width="1" height="1"><img src="/fallback.jpg">]]></description>
        <media:thumbnail url="//cdn.example.com/photo.jpg?source=x&amp;ref=y&amp;sig=a%2Bb"/>
        </item></channel></rss>'''
        row = self.backend.parse_feed({'name':'Example'}, xml.encode(), NOW)[0]
        self.assertEqual(row['image_url'], 'https://cdn.example.com/photo.jpg?source=x&ref=y&sig=a%2Bb')
        self.assertNotIn('<img', row['feed_summary'])
        signed = 'https://example.com/a.png?copy=1&not=2&ref=x'
        self.assertEqual(self.images.image_url(signed), signed)
        node = ET.fromstring('<item/>')
        self.assertEqual(self.images.extract_image(node, '<img src="x" width="1"><img src="../pic.png">', 'https://example.com/news/story'), 'https://example.com/pic.png')
        for bad in ['data:image/png,abc', 'file:///tmp/a', 'https://u:p@example.com/a', 'javascript:alert(1)']:
            self.assertEqual(self.images.image_url(bad), '')

    def test_atom_enclosure_xhtml_and_no_image(self):
        raw = '''<feed xmlns="http://www.w3.org/2005/Atom"><entry><title>Atom story</title>
        <link href="https://example.com/a"/><link rel="enclosure" type="image/jpeg" href="https://example.com/a.jpg"/>
        </entry></feed>'''
        self.assertEqual(self.backend.parse_feed({'name':'Example'}, raw.encode(), NOW)[0]['image_url'], 'https://example.com/a.jpg')
        node = ET.fromstring('<entry xmlns="http://www.w3.org/2005/Atom"><content><div xmlns="http://www.w3.org/1999/xhtml"><img src="/a.png"/></div></content></entry>')
        self.assertEqual(self.images.extract_image(node, '', 'https://example.com/a'), 'https://example.com/a.png')
        self.assertEqual(self.images.extract_image(ET.fromstring('<item/>'), 'text', 'https://example.com'), '')
        broken = ET.fromstring('<item xmlns:media="http://search.yahoo.com/mrss/"><media:content url="http://[invalid"/></item>')
        self.assertEqual(self.images.extract_image(broken, '', 'https://example.com'), '')

    def test_disabled_endpoint_never_downloads_or_creates_cache(self):
        with mock.patch.object(self.images, 'cached_image') as fetch:
            self.assertEqual(self.backend.article_images('["story"]'), {'ok':True,'images':{}})
        fetch.assert_not_called()
        for value in ['{}', '[1]', json.dumps(['a']*5)]:
            with self.assertRaises(ValueError): self.backend.article_images(value)

    def test_enabled_endpoint_uses_saved_article_id_only_and_not_remote_input(self):
        self.backend.set_article_images(True)
        conn = self.backend.db()
        conn.execute('INSERT INTO articles(id,url,title,source,published_ts,fetched_ts,image_url) VALUES(?,?,?,?,?,?,?)',
                     ('story','https://example.com/a','Story','Example',NOW,NOW,'https://example.com/p.png'))
        conn.commit(); conn.close()
        with mock.patch.object(self.images, 'cached_image', return_value='file:///tmp/local.img') as fetch:
            result = self.backend.article_images('["story","missing","https://arbitrary.example/image"]')
        fetch.assert_called_once()
        self.assertEqual(fetch.call_args.args[0], 'https://example.com/p.png')
        self.assertEqual(result['images']['story'], 'file:///tmp/local.img')
        self.assertEqual(result['images']['missing'], '')

    def test_cache_hit_failure_backoff_and_size_guards(self):
        url = 'https://example.com/a.png'
        with mock.patch.object(self.images, 'download_image', return_value=png()) as fetch:
            path = self.images.cached_image(url, self.cache)
            self.assertTrue(path.startswith('file://'))
            self.assertEqual(self.images.cached_image(url, self.cache), path)
            fetch.assert_called_once()
        for name, data in [('bomb',png(6000,6000)),('pixel',png(1,1)),('svg',b'<svg/>'),('large',png()+b'x'*(self.images.MAX_BYTES+1))]:
            with mock.patch.object(self.images, 'download_image', return_value=data) as fetch:
                self.assertEqual(self.images.cached_image('https://example.com/'+name,self.cache),'')
                self.assertEqual(self.images.cached_image('https://example.com/'+name,self.cache),'')
                fetch.assert_called_once()

    def test_cache_expiry_count_and_byte_budget(self):
        self.cache.mkdir()
        for i in range(135):
            path = self.cache / (str(i)+'.miss'); path.write_bytes(b'')
        old = self.cache/'expired.img'; old.write_bytes(png()); os.utime(old,(1,1))
        with mock.patch.object(self.images,'download_image',return_value=png()):
            self.images.cached_image('https://example.com/new',self.cache)
        files = list(self.cache.glob('*.img'))+list(self.cache.glob('*.miss'))
        self.assertLessEqual(len(files),self.images.CACHE_FILES)
        self.assertLessEqual(sum(p.stat().st_size for p in files),self.images.CACHE_BYTES)
        self.assertFalse(old.exists())

    def test_private_dns_targets_are_rejected_before_connect(self):
        for address in ['127.0.0.1','10.1.2.3','169.254.169.254','::1']:
            with mock.patch.object(self.images.socket,'getaddrinfo',return_value=[(2,1,6,'',(address,443))]), mock.patch.object(self.images.socket,'create_connection') as connect:
                with self.assertRaises(ValueError): self.images.download_image('https://example.com/image')
                connect.assert_not_called()

    def test_existing_database_migrates_without_changing_articles_or_read_state(self):
        conn = self.backend.db()
        conn.execute('INSERT INTO articles(id,url,title,source,published_ts,fetched_ts) VALUES(?,?,?,?,?,?)',('old','https://example.com/a','Old title','Example',NOW,NOW))
        conn.execute('INSERT INTO read_articles(article_id,read_ts,group_root) VALUES(?,?,?)',('old',NOW,'old'))
        conn.commit(); conn.execute('ALTER TABLE articles DROP COLUMN image_url'); conn.commit(); conn.close()
        conn = self.backend.db()
        self.assertEqual(conn.execute('SELECT title,image_url FROM articles WHERE id="old"').fetchone()[:],('Old title',''))
        self.assertEqual(conn.execute('SELECT article_id FROM read_articles').fetchone()[0],'old')
        conn.close()
