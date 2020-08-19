from functools import lru_cache

import connexion
from elasticsearch import Elasticsearch

import config


es = Elasticsearch()


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


def find(body):
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
        return connexion.problem(
            status=400,
            title='Bad request',
            detail='must provide at least one filter',
        )

    query = {"bool": {"filter": filters}}
    res = es.search(index=config.ES_INDEX_NAME, body={"query": query})

    libcs = []
    for hit in res['hits']['hits']:
        doc = hit['_source']
        id = doc['id']

        result_symbols = {}
        syms = get_symbols(id)
        if symbol_filters:
            for s in symbol_filters.keys():
                if s in syms:
                    result_symbols[s] = f'{syms[s]:#x}'

        libcs.append({
            'id': id,
            'buildid': doc.get('buildid'),
            'sha1': doc.get('sha1'),
            'md5': doc.get('md5'),
            'sha256': doc.get('sha256'),
            'symbols': result_symbols,
            'download_url': 'http://foo.bar',
        })
    return libcs



app = connexion.App(__name__, specification_dir='.')
app.add_api('api.yml')


if __name__ == '__main__':
    app.run(port=8080, host='127.0.0.1', debug=True)
