# -*- coding: utf-8 -*-
"""把安装包和补丁发到 Gitee Release（国内源），并验证匿名直链可下载、支持 Range。

用法：
    python tool/upload_gitee.py 2.27.1

前置：
    C:\\Users\\18814\\.chaomu_gitee.json
    {
      "owner": "你的 Gitee 用户名",
      "repo": "chaomu",
      "token": "私人令牌"
    }

做四件事：
1. 仓库不存在就建（公开）
2. Release 不存在就建
3. 传 手机安装包\\朝暮-<版本>.apk / <旧>-to-<新>.patch / 电脑安装包\\朝暮-<版本>-windows.zip
   （Gitee 附件名用 ASCII：chaomu-<版本>-arm64.apk 等）
4. 打印直链，并匿名实测速度 + Range
"""
import json
import os
import sys
import time

import requests

API = 'https://gitee.com/api/v5'
CFG_PATH = os.path.join(os.path.expanduser('~'), '.chaomu_gitee.json')
DESKTOP = os.path.join(os.path.expanduser('~'), 'Desktop', '朝暮')


def load_cfg():
    if not os.path.isfile(CFG_PATH):
        raise SystemExit('缺少配置文件：%s' % CFG_PATH)
    return json.load(open(CFG_PATH, encoding='utf-8'))


def ensure_repo(owner, repo, token):
    r = requests.get('%s/repos/%s/%s' % (API, owner, repo),
                     params={'access_token': token}, timeout=30)
    if r.status_code == 200:
        pub = r.json().get('public')
        print('仓库已存在，公开=%s' % pub)
        if not pub:
            print('！仓库是私有的，改成公开才能匿名下载附件')
        return
    if r.status_code == 404:
        print('仓库不存在，新建公开仓库…')
        r = requests.post('%s/user/repos' % API, data={
            'access_token': token,
            'name': repo,
            'private': 'false',
            'auto_init': 'true',
            'description': '朝暮安装包国内下载源',
        }, timeout=60)
        if r.status_code not in (200, 201):
            raise SystemExit('建仓库失败 %s %s' % (r.status_code, r.text[:300]))
        print('仓库已建')
        return
    raise SystemExit('查询仓库失败 %s %s' % (r.status_code, r.text[:300]))


def ensure_release(owner, repo, token, tag):
    r = requests.get('%s/repos/%s/%s/releases/tags/%s' % (API, owner, repo, tag),
                     params={'access_token': token}, timeout=30)
    # Gitee 查不到时返回 200 + 字面量 null，不是 404，必须判空
    if r.status_code == 200:
        try:
            got = r.json()
        except Exception:
            got = None
        if isinstance(got, dict) and got.get('id'):
            print('Release 已存在 id=%s' % got['id'])
            return got['id']
    r = requests.post('%s/repos/%s/%s/releases' % (API, owner, repo), data={
        'access_token': token,
        'tag_name': tag,
        'name': '朝暮 %s' % tag,
        'body': '朝暮 %s 安装包，国内源。' % tag,
        'target_commitish': 'master',
    }, timeout=60)
    if r.status_code not in (200, 201):
        raise SystemExit('建 Release 失败 %s %s' % (r.status_code, r.text[:300]))
    print('Release 已建 id=%s' % r.json().get('id'))
    return r.json()['id']


def upload_attach(owner, repo, token, rid, path, name):
    size = os.path.getsize(path)
    print('上传 %s (%.1f MB)…' % (name, size / 1048576))
    t0 = time.time()
    with open(path, 'rb') as f:
        r = requests.post(
            '%s/repos/%s/%s/releases/%s/attach_files' % (API, owner, repo, rid),
            data={'access_token': token},
            files={'file': (name, f, 'application/octet-stream')},
            timeout=1800)
    if r.status_code not in (200, 201):
        raise SystemExit('上传失败 %s %s' % (r.status_code, r.text[:300]))
    dt = time.time() - t0
    print('  完成，用时 %.1f 秒，上传 %.0f KB/s' % (dt, size / 1024 / max(dt, 0.1)))
    return r.json()


def probe(url):
    print('匿名测速 %s' % url)
    try:
        r = requests.get(url, stream=True, timeout=30,
                         headers={'Range': 'bytes=0-1048575'})
        print('  HTTP %s  Accept-Ranges=%s  Content-Length=%s' % (
            r.status_code, r.headers.get('Accept-Ranges'), r.headers.get('Content-Length')))
        got = 0
        t0 = time.time()
        for chunk in r.iter_content(65536):
            got += len(chunk)
            if got >= 1048576 or time.time() - t0 > 20:
                break
        dt = time.time() - t0
        print('  实测 %.0f KB/s（1 MB 用了 %.1f 秒）' % (got / 1024 / max(dt, 0.1), dt))
    except Exception as e:
        print('  测速失败：%s' % e)


def main():
    ver = sys.argv[1] if len(sys.argv) > 1 else None
    if not ver:
        raise SystemExit('用法：python tool/upload_gitee.py 2.27.1')
    cfg = load_cfg()
    owner, repo, token = cfg['owner'], cfg['repo'], cfg['token']

    apk_dir = os.path.join(DESKTOP, '手机安装包')
    pc_dir = os.path.join(DESKTOP, '电脑安装包')
    apk_src = os.path.join(apk_dir, '朝暮-%s.apk' % ver)
    zip_src = os.path.join(pc_dir, '朝暮-%s-windows.zip' % ver)
    if not os.path.isfile(apk_src):
        raise SystemExit('找不到 %s' % apk_src)

    files = [(apk_src, 'chaomu-%s-arm64.apk' % ver)]
    if os.path.isfile(zip_src):
        files.append((zip_src, 'chaomu-%s-windows-x64.zip' % ver))
    for f in sorted(os.listdir(apk_dir)):
        if f.endswith('.patch') and f.endswith('-to-%s.patch' % ver):
            files.append((os.path.join(apk_dir, f), f))

    ensure_repo(owner, repo, token)
    tag = 'v%s' % ver
    rid = ensure_release(owner, repo, token, tag)

    urls = []
    for src, name in files:
        info = upload_attach(owner, repo, token, rid, src, name)
        url = 'https://gitee.com/%s/%s/releases/download/%s/%s' % (owner, repo, tag, name)
        urls.append(url)
        print('  直链 %s' % url)

    print()
    print('=== 匿名验证 ===')
    for u in urls:
        probe(u)


if __name__ == '__main__':
    main()
