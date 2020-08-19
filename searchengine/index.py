import argparse
import elasticsearch
import glob
import hashlib
import logging
import os
import re
import sys
from datetime import datetime
from elasticsearch import Elasticsearch
from subprocess import check_output, DEVNULL

import config


log = logging.getLogger('indexer')


BUILD_ID_REGEX = re.compile('Build ID: ([a-fA-F0-9]+)')

def get_build_id(fname):
    try:
        res = check_output(['readelf', '-n', fname], stderr=DEVNULL).decode()
    except Exception:
        return None
    m = BUILD_ID_REGEX.search(res)
    if m:
        return m.group(1)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)

    p = argparse.ArgumentParser()
    p.add_argument('--index', default=config.ES_INDEX_NAME)
    p.add_argument('--fresh', action='store_true')
    p.add_argument('dir')
    args = p.parse_args()

    es = Elasticsearch()

    if args.fresh:
        es.indices.delete(args.index, ignore=[404])

    es.indices.create(args.index, ignore=[400])
    es.indices.put_mapping(index=args.index, doc_type='libc', body={
        'libc': {
            "properties": {
                "symbols": {
                    "type": "text",
                    "analyzer": "whitespace"
                },
                "sha1": {
                    "type": "keyword",
                },
                "md5": {
                    "type": "keyword",
                },
                "sha256": {
                    "type": "keyword",
                },
                "buildid": {
                    "type": "keyword",
                },
                "id": {
                    "type": "keyword",
                },
            }
        }
    }, include_type_name=True)

    dir = os.path.abspath(args.dir)
    for libc_fname in glob.glob(f'{dir}/*.so'):
        id, _ = os.path.splitext(os.path.basename(libc_fname))
        log.info(f'{id}: indexing')
        res = es.get(index=args.index, id=id, ignore=[404])
        if res['found']:
            log.info(f'{id}: already exists')
            continue
        doc = {
            'id': id,
            'timestamp': datetime.now(),
        }
        syms = []
        with open(f'{dir}/{id}.symbols') as f:
            for line in f:
                if not line.strip():
                    continue
                name, addr = line.split()
                addr = int(addr, 16)
                syms.append(f'{name}@{addr & 0xfff:03x}')
        doc['symbols'] = ' '.join(syms)
        with open(libc_fname, 'rb') as f:
            libc = f.read()
        doc['sha1'] = hashlib.sha1(libc).hexdigest()
        doc['sha256'] = hashlib.sha256(libc).hexdigest()
        doc['md5'] = hashlib.md5(libc).hexdigest()
        buildid = get_build_id(libc_fname)
        if buildid:
            doc['buildid'] = buildid
        es.create(index=args.index, id=id, body=doc)

    es.indices.refresh(index=args.index)

    # res = es.search(index=args.index, body={"query": {"match": {"sha1": "102be3798e5d42044fb6b8f072ef609ef33ee5bf"}}})
    # res = es.search(index=args.index, body={"query": {"match": {"buildid": "28a5cf977adc27c69ca78bedd595096dd1977a7d"}}})
    # res = es.search(index=args.index, body={"query": {"term": {"symbols": "faccessat@190"}}})
    # print("Got %d Hits:" % res['hits']['total']['value'])
    # for hit in res['hits']['hits']:
        # s = hit['_source']
        # print(f"Found {s['id']}")
