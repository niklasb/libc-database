import os

ES_INDEX_NAME = 'test-index'
DB_DIR = os.path.dirname(os.path.abspath(__file__)) + '/../db'
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
