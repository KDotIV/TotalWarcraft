"""Offline publishing safeguards: no credentials or live uploads are used."""
import contextlib
from email.parser import BytesParser
from email.policy import default
import io
import json
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import publish_curseforge as publish

for tag in ['main', 'v0.7.1', 'v' + publish.VERSION + '-dev', 'v' + publish.VERSION + '-alpha']:
    try:
        publish.prepare(tag)
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid release tag accepted: ' + tag)

archive, manifest, metadata = publish.prepare('v' + publish.VERSION)
assert manifest['flavor'] == 'release' and metadata['releaseType'] == 'release'
assert not metadata['isMarkedForManualRelease']
assert metadata['changelog'].startswith('TotalWarcraft ' + publish.VERSION)
assert publish.forever_version_id([{'name': '1.60.1', 'gameVersionTypeID': 88568, 'id': 77}]) == 77
for rows in [[], [{'name':'1.60.1', 'gameVersionTypeID':517, 'id':77}],
             [{'name':'1.60.2', 'gameVersionTypeID':88568, 'id':77}],
             [{'name':'1.60.1', 'gameVersionTypeID':88568, 'id':77}]*2]:
    try:
        publish.forever_version_id(rows)
    except ValueError:
        pass
    else:
        raise AssertionError('Unknown/ambiguous client accepted')

body, content_type = publish.multipart(metadata, archive)
message = BytesParser(policy=default).parsebytes(('Content-Type: '+content_type+'\r\n\r\n').encode()+body)
parts = list(message.iter_parts())
assert json.loads(parts[0].get_payload(decode=True)) == metadata
assert parts[1].get_filename() == archive.name
assert parts[1].get_payload(decode=True) == archive.read_bytes()

with patch.object(sys, 'argv', ['publish', '--tag', 'v'+publish.VERSION, '--check']), \
     patch.object(publish, 'api_json') as api, contextlib.redirect_stdout(io.StringIO()):
    publish.main()
    api.assert_not_called()
with patch.object(sys, 'argv', ['publish', '--tag', 'v'+publish.VERSION]), \
     patch.dict(publish.os.environ, {'CF_API_TOKEN':''}), patch.object(publish, 'api_json') as api:
    try:
        publish.main()
    except ValueError as error:
        assert 'Missing CF_API_TOKEN' in str(error)
    else:
        raise AssertionError('Missing credential accepted')
    api.assert_not_called()
assert publish.NoRedirect().redirect_request(None,None,302,'',{},'https://example.com') is None
print('PASS: strict Release tag/changelog, production archive, exact Forever version, multipart bytes, offline checks, missing-secret failure and credential redirect refusal.')
