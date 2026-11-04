# -*- coding: utf-8 -*-
"""生成并推送 latest.json 到 Gitee 仓库根目录（国内源的版本索引）。

用法：
    python tool/gen_latest_json.py 2.27.2

做三件事：
1. 从 CHANGELOG.md 取该版本的「更新摘要」第一条当 notes
2. 在 桌面\\朝暮\\手机安装包 里找 `<旧>-to-<新>.patch`，把补丁信息写进去
3. 推 latest.json 到 gitee 仓库（有就更新，没有就新建）

App 端 `Updater._checkChina()` 读的就是这个文件。
"""
import base64
import json
import os
import re
import sys

import requests

API = 'https://gitee.com/api/v5'
CFG_PATH = os.path.join(os.path.expanduser('~'), '.chaomu_gitee.json')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APK_DIR = os.path.join(os.path.expanduser('~'), 'Desktop', '朝暮', '手机安装包')


def read_notes(ver):
    p = os.path.join(ROOT, 'CHANGELOG.md')
    txt = open(p, encoding='utf-8').read()
    m = re.search(r'##\s*%s\+?\d*\s*[—-][^\n]*\n(.*?)(?=\n##\s)' % re.escape(ver),
                  txt, re.S)
    if not m:
        return ''
    body = m.group(1)
    hit = re.search(r'###\s*更新摘要\s*\n+(.*?)(?=\n###|\Z)', body, re.S)
    if not hit:
        return ''
    for line in hit.group(1).splitlines():
        line = line.strip()
        if line.startswith('-'):
            return line.lstrip('- ').strip()
    return ''


def find_patch(ver):
    """找指向本版本的补丁，取源版本号最大的那个。"""
    best = None
    if not os.path.isdir(APK_DIR):
        return None
    for f in os.listdir(APK_DIR):
        m = re.match(r'^([\d.]+)-to-%s\.patch$' % re.escape(ver), f)
        if not m:
            continue
        key = [int(x) for x in m.group(1).split('.')]
        if best is None or key > best[0]:
            best = (key, m.group(1), f)
    if not best:
        return None
    path = os.path.join(APK_DIR, best[2])
    return {'from': best[1], 'file': best[2], 'size': os.path.getsize(path)}


def main():
    if len(sys.argv) < 2:
        raise SystemExit('用法：python tool/gen_latest_json.py 2.27.2')
    ver = sys.argv[1]
    cfg = json.load(open(CFG_PATH, encoding='utf-8'))
    owner, repo, token = cfg['owner'], cfg['repo'], cfg['token']
    tag = 'v%s' % ver
    dl = 'https://gitee.com/%s/%s/releases/download/%s/' % (owner, repo, tag)

    doc = {
        'latest': ver,
        'notes': read_notes(ver),
        'page': 'https://gitee.com/%s/%s/releases' % (owner, repo),
        'apk': dl + 'chaomu-%s-arm64.apk' % ver,
        'win': dl + 'chaomu-%s-windows-x64.zip' % ver,
        'patches': [],
    }
    p = find_patch(ver)
    if p:
        doc['patches'].append({
            'from': p['from'],
            'url': dl + p['file'],
            'size': p['size'],
        })

    raw = json.dumps(doc, ensure_ascii=False, indent=2).encode('utf-8')
    print(raw.decode())

    api = '%s/repos/%s/%s/contents/latest.json' % (API, owner, repo)
    r = requests.get(api, params={'access_token': token}, timeout=30)
    sha = None
    if r.status_code == 200:
        try:
            sha = r.json().get('sha')
        except Exception:
            sha = None
    payload = {
        'access_token': token,
        'content': base64.b64encode(raw).decode(),
        'message': 'latest.json -> %s' % ver,
    }
    if sha:
        payload['sha'] = sha
        r = requests.put(api, data=payload, timeout=60)
    else:
        r = requests.post(api, data=payload, timeout=60)
    print('推送 latest.json: HTTP %s' % r.status_code)
    if r.status_code not in (200, 201):
        raise SystemExit(r.text[:300])
    print('索引地址 https://gitee.com/%s/%s/raw/master/latest.json' % (owner, repo))


if __name__ == '__main__':
    main()
