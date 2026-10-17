"""把 pubspec.yaml 的版本号同步进 android/local.properties。

为什么需要这一步：

    正常跑 `flutter build apk` 时，Flutter 工具链会先把 pubspec.yaml 里的
    `version: 2.7.4+6` 拆成 versionName / versionCode 写进 android/local.properties，
    然后才调 Gradle。Gradle 读的是 local.properties 里那两个值，不是 pubspec。

    而这个工程在沙箱里打包是**绕过 flutter.bat 直接调 gradlew** 的（flutter.bat
    在沙箱里起不来），同步那一步就被跳过了 —— 结果 local.properties 一直停在
    老版本号，打出来的 APK versionName 永远是旧的。

用法（打包前必跑）：

    python tool/sync_version.py

跑完会打印改了什么。改完再执行 gradlew assembleRelease。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PUBSPEC = os.path.join(ROOT, 'pubspec.yaml')
LOCAL_PROPS = os.path.join(ROOT, 'android', 'local.properties')


def read_pubspec_version():
    with open(PUBSPEC, encoding='utf-8') as f:
        for line in f:
            m = re.match(r'^version:\s*(\S+)\s*$', line)
            if m:
                return m.group(1)
    raise SystemExit('pubspec.yaml 里找不到 version:')


def split_version(v):
    # 2.7.4+6 -> ('2.7.4', '6')
    if '+' in v:
        name, code = v.split('+', 1)
    else:
        name, code = v, '1'
    return name.strip(), code.strip()


def main():
    version = read_pubspec_version()
    name, code = split_version(version)

    if not os.path.exists(LOCAL_PROPS):
        raise SystemExit('找不到 android/local.properties')

    with open(LOCAL_PROPS, encoding='utf-8') as f:
        text = f.read()

    old_name = re.search(r'^flutter\.versionName=(.*)$', text, re.M)
    old_code = re.search(r'^flutter\.versionCode=(.*)$', text, re.M)
    old_name = old_name.group(1).strip() if old_name else '(无)'
    old_code = old_code.group(1).strip() if old_code else '(无)'

    # 有就替换，没有就补一行
    if re.search(r'^flutter\.versionName=.*$', text, re.M):
        text = re.sub(r'^flutter\.versionName=.*$', 'flutter.versionName=' + name, text, flags=re.M)
    else:
        text += 'flutter.versionName=' + name + '\n'

    if re.search(r'^flutter\.versionCode=.*$', text, re.M):
        text = re.sub(r'^flutter\.versionCode=.*$', 'flutter.versionCode=' + code, text, flags=re.M)
    else:
        text += 'flutter.versionCode=' + code + '\n'

    with open(LOCAL_PROPS, 'w', encoding='utf-8', newline='') as f:
        f.write(text)

    print('pubspec.yaml        version = %s' % version)
    print('local.properties    versionName: %s -> %s' % (old_name, name))
    print('local.properties    versionCode: %s -> %s' % (old_code, code))
    if old_name == name and old_code == code:
        print('（本来就是最新的，没变化）')
    else:
        print('已同步。现在可以跑 gradlew assembleRelease 了。')


if __name__ == '__main__':
    sys.exit(main())
