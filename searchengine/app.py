import logging
from functools import lru_cache
from pathlib import Path

from connexion import AsyncApp, problem
from connexion.middleware import MiddlewarePosition
from starlette.middleware.cors import CORSMiddleware
from elasticsearch import Elasticsearch

import config


es = Elasticsearch(hosts=[config.ES_HOST])
log = logging.getLogger('wsgi')

log.info(f'Using elasticsearch server {config.ES_HOST}, index {config.ES_INDEX_NAME}')

DEFAULT_FIND_LIMIT = 10
MAX_FIND_LIMIT = 100


@lru_cache(maxsize=2000)
def get_symbols(id):
    syms = {}
    with open(f'{config.DB_DIR}/{id}.symbols') as f:
        for line in f:
            if not line.strip():
                continue
            name, addr = line.split()
            addr = int(addr, 16)
            syms[name] = addr
    return syms


@lru_cache(maxsize=2000)
def get_libs_url(id):
    with open(f'{config.DB_DIR}/{id}.url') as f:
        return f.read().strip()


def _parse_pagination(limit, offset):
    try:
        limit = DEFAULT_FIND_LIMIT if limit is None else int(limit)
        offset = 0 if offset is None else int(offset)
    except (TypeError, ValueError):
        return problem(
            status=400,
            title='Bad request',
            detail='limit and offset must be integers',
        )

    if limit < 1 or limit > MAX_FIND_LIMIT:
        return problem(
            status=400,
            title='Bad request',
            detail=f'limit must be between 1 and {MAX_FIND_LIMIT}',
        )

    if offset < 0:
        return problem(
            status=400,
            title='Bad request',
            detail='offset must be non-negative',
        )

    return limit, offset


def _search_libcs(body, extra_symbols=None, limit=DEFAULT_FIND_LIMIT, offset=0, include_metadata=True):
    extra_symbols = extra_symbols or []
    filters = []

    for h in ('id', 'md5', 'sha1', 'sha256', 'buildid'):
        if h in body:
            filters.append({'match': {h: body[h]}})

    symbol_filters = body.get('symbols')
    if symbol_filters:
        terms = []
        for sym, addr in symbol_filters.items():
            addr = int(addr, 16)
            term = f'{sym}@{addr & 0xfff:03x}'
            filters.append({'term': {'symbols': term}})


    if not filters:
        return problem(
            status=400,
            title='Bad request',
            detail='must provide at least one filter',
        )

    query = {"bool": {"filter": filters}}
    res = es.search(
        index=config.ES_INDEX_NAME,
        query=query,
        from_=offset,
        size=limit,
        track_total_hits=True,
    )

    libcs = []
    for hit in res['hits']['hits']:
        doc = hit['_source']
        id = doc['id']
        syms = get_symbols(id)

        result_symbols = {}

        names = list(config.DEFAULT_SYMBOLS) + extra_symbols
        if symbol_filters:
            names += symbol_filters.keys()
        for name in names:
            if name in syms:
                result_symbols[name] = f'{syms[name]:#x}'

        libcs.append({
            'id': id,
            'buildid': doc.get('buildid'),
            'sha1': doc.get('sha1'),
            'md5': doc.get('md5'),
            'sha256': doc.get('sha256'),
            'symbols': result_symbols,
            'download_url': config.DOWNLOAD_URL.format(id),
            'symbols_url': config.ALL_SYMBOLS_URL.format(id),
            'libs_url': get_libs_url(id),
        })

    total = res['hits']['total']
    if isinstance(total, dict):
        total = total.get('value', len(libcs))

    if not include_metadata:
        return libcs

    return {
        'results': libcs,
        'total': total,
        'limit': limit,
        'offset': offset,
        'count': len(libcs),
        'has_more': offset + len(libcs) < total,
    }


def find(body, limit=None, offset=None, extra_symbols=[]):
    include_metadata = limit is not None or offset is not None
    pagination = _parse_pagination(limit, offset)
    if not isinstance(pagination, tuple):
        return pagination

    limit, offset = pagination
    return _search_libcs(
        body,
        extra_symbols=extra_symbols,
        limit=limit,
        offset=offset,
        include_metadata=include_metadata,
    )


def dump(id, body):
    res = _search_libcs(
        {'id': id},
        extra_symbols=body.get('symbols', []),
        limit=1,
        include_metadata=False,
    )
    if not res:
        return problem(
            status=404,
            title='Not found',
            detail=f'Unknown ID: {id}'
        )

    return res[0]


app = AsyncApp(__name__, specification_dir='.')
app.add_middleware(
    CORSMiddleware,
    position=MiddlewarePosition.BEFORE_EXCEPTION,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.add_api('api.yml')

if __name__ == '__main__':
    app.run(f"{Path(__file__).stem}:app",port=8080, host='127.0.0.1', debug=True)
