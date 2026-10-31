#!/usr/bin/env python3
"""One release number per publication; rebuilding never increments it."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import tempfile
from zoneinfo import ZoneInfo

VERSION_FILE = Path(__file__).resolve().parents[1] / 'Release/version.json'

def metadata(value):
    date, sequence = value['date'], value['sequence']
    if not isinstance(date, str) or not re.fullmatch(r'\d{8}', date):
        raise ValueError('日期须为 YYYYMMDD')
    parsed = dt.datetime.strptime(date, '%Y%m%d').date()
    if parsed.strftime('%Y%m%d') != date or type(sequence) is not int or not 1 <= sequence <= 99:
        raise ValueError('当天发布序号须为 01 至 99')
    return {'display': f'{date}({sequence:02d})', 'build': f'{date}.{sequence}',
            'tag': f'v{date}-{sequence:02d}', 'asset': f'Guiyu-{date}-{sequence:02d}-macOS-arm64.zip'}

def next_release(value, date):
    metadata(value)
    if date < value['date']:
        raise ValueError('发布日期不能早于当前版本')
    result = {'date': date, 'sequence': value['sequence'] + 1 if date == value['date'] else 1}
    metadata(result)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--next', action='store_true', help='发布新版本时推进一次序号')
    parser.add_argument('--date', default=dt.datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y%m%d'))
    args = parser.parse_args()
    value = json.loads(VERSION_FILE.read_text())
    if args.next:
        value = next_release(value, args.date)
        with tempfile.NamedTemporaryFile(mode='w', dir=VERSION_FILE.parent, delete=False) as stream:
            json.dump(value, stream); stream.write('\n'); staged = stream.name
        os.replace(staged, VERSION_FILE)
    print(json.dumps(metadata(value), ensure_ascii=False))

if __name__ == '__main__':
    main()
