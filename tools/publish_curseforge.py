"""Upload only our compiled production ZIP. Never log or accept a token argument."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import urllib.error
import urllib.request

from build_addon import ROOT, VERSION, build

PROJECT_ID = 1819796
GAME_VERSION = '1.60.1'
FOREVER_TYPE_ID = 88568
API = 'https://wow.curseforge.com/api'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Do not forward the publishing credential to a redirected destination.
        return None


def api_json(path, token, body=None, content_type=None):
    headers = {'X-Api-Token': token, 'Accept': 'application/json',
               'User-Agent': 'TotalWarcraft-release-workflow'}
    if content_type:
        headers['Content-Type'] = content_type
    request = urllib.request.Request(API + path, data=body, headers=headers)
    try:
        with urllib.request.build_opener(NoRedirect).open(request, timeout=60) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'CurseForge returned HTTP {error.code}. Check the author portal before retrying.') from None
    except (urllib.error.URLError, TimeoutError, ValueError):
        raise RuntimeError('CurseForge response unavailable. Check the author portal before retrying; uploads are not retried automatically.') from None


def forever_version_id(rows):
    matches = [row.get('id') for row in rows if isinstance(row, dict)
               and row.get('name') == GAME_VERSION
               and row.get('gameVersionTypeID') == FOREVER_TYPE_ID]
    if len(matches) != 1 or type(matches[0]) is not int or matches[0] <= 0:
        raise ValueError('Expected exactly one WoW Forever 1.60.1 API version. Refusing to guess another client/version.')
    return matches[0]


def prepare(tag):
    if not re.fullmatch(r'v\d+\.\d+\.\d+', tag) or tag != 'v' + VERSION:
        raise ValueError(f'Release tag must exactly match v{VERSION}; alpha/dev tags cannot publish a Release.')
    changelog = (ROOT / 'WarbandPvP' / 'CHANGELOG.txt').read_text(encoding='utf-8')
    if not changelog.startswith('TotalWarcraft ' + VERSION + '\n'):
        raise ValueError('CHANGELOG.txt must begin with the exact release name/version.')
    _, manifest = build('release')
    if manifest['flavor'] != 'release' or manifest['version'] != VERSION:
        raise ValueError('Only the production flavor may be published.')
    archive = Path(manifest['zip'])
    if hashlib.sha256(archive.read_bytes()).hexdigest() != manifest['sha256']:
        raise ValueError('Release archive hash mismatch.')
    # Publish this version's notes; retain older history in the packaged file.
    current_changes = changelog.split('\nTotalWarcraft ', 1)[0].rstrip() + '\n'
    metadata = {'displayName': 'TotalWarcraft ' + VERSION,
                'releaseType': 'release', 'changelogType': 'text',
                'changelog': current_changes, 'isMarkedForManualRelease': False}
    return archive, manifest, metadata


def multipart(metadata, archive):
    boundary = 'TotalWarcraft-' + secrets.token_hex(16)
    body = ('--' + boundary + '\r\nContent-Disposition: form-data; name="metadata"\r\n'
            'Content-Type: application/json\r\n\r\n' + json.dumps(metadata) + '\r\n').encode()
    body += ('--' + boundary + '\r\nContent-Disposition: form-data; name="file"; filename="'
             + archive.name + '"\r\nContent-Type: application/zip\r\n\r\n').encode()
    body += archive.read_bytes() + ('\r\n--' + boundary + '--\r\n').encode()
    return body, 'multipart/form-data; boundary=' + boundary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tag', required=True)
    parser.add_argument('--check', action='store_true', help='Validate/build locally without credentials or network access')
    args = parser.parse_args()
    archive, manifest, metadata = prepare(args.tag)
    if args.check:
        print(json.dumps({'project': PROJECT_ID, 'version': VERSION, 'releaseType': 'release',
                          'zip': archive.name, 'sha256': manifest['sha256'], 'gameVersion': GAME_VERSION}))
        return
    token = os.environ.get('CF_API_TOKEN', '').strip()
    if not token:
        raise ValueError('Missing CF_API_TOKEN GitHub Actions secret. Add it in repository Settings > Secrets and variables > Actions.')
    metadata['gameVersions'] = [forever_version_id(api_json('/game/versions', token))]
    body, content_type = multipart(metadata, archive)
    result = api_json(f'/projects/{PROJECT_ID}/upload-file', token, body, content_type)
    file_id = result.get('id') if isinstance(result, dict) else None
    if type(file_id) is not int or file_id <= 0:
        raise ValueError('Upload response did not confirm a file ID. Check the portal before retrying.')
    receipt = {'project': PROJECT_ID, 'file': file_id, 'version': VERSION,
               'sha256': manifest['sha256'], 'releaseType': 'release',
               'url': f'https://www.curseforge.com/wow/addons/total-warcraft/files/{file_id}'}
    (ROOT / 'releases' / 'curseforge-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))
    summary = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary:
        with open(summary, 'a', encoding='utf-8') as stream:
            stream.write(f"Uploaded TotalWarcraft {VERSION} as Release: [file {file_id}]({receipt['url']}).\n\n"
                         'CurseForge moderation and client indexing may still be pending.\n')


if __name__ == '__main__':
    try:
        main()
    except (ValueError, RuntimeError) as error:
        raise SystemExit(str(error)) from None
