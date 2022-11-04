import os

ES_INDEX_NAME = 'libcsearch'

# ES_HOST = 'http://localhost:9200'
ES_HOST = 'http://es01:9200'

# DB_DIR = os.path.dirname(os.path.abspath(__file__)) + '/../db'
DB_DIR = '/db'

DEFAULT_SYMBOLS = [
    '__libc_start_main_ret',
    'system',
    'dup2',
    'str_bin_sh',
    'read',
    'write',
    'puts',
    'printf',
]
DOWNLOAD_URL = 'https://libc.rip/download/{}.so'
ALL_SYMBOLS_URL = 'https://libc.rip/download/{}.symbols'
