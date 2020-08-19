# libc-database web service

Full OpenAPI spec: https://github.com/niklasb/libc-database/blob/master/searchengine/api.yml

Hosted at https://libc.rip/api/


You can search by symbol:

```
$ curl -X POST -H 'Content-Type: application/json' --data \
     '{"symbols": {"strncpy": "db0", "strcat": "0x000000000d800"}}' \
     'https://libc.rip/api/find'
[
  {
    "buildid": "d3cf764b2f97ac3efe366ddd07ad902fb6928fd7",
    "download_url": "https://libc.rip/download/libc6_2.27-3ubuntu1.2_amd64.so",
    "id": "libc6_2.27-3ubuntu1.2_amd64",
    "md5": "35ef4ffc9c6ad7ffd1fd8c16f14dc766",
    "sha1": "a22321cd65f28f70cf321614fdfd22f36ecd0afe",
    "sha256": "f0ad9639b2530741046e06c96270b25da2339b6c15a7ae46de8fb021b3c4f529",
    "symbols": {
      ...
    }
  }
]
```

Or by hash (buildid, sha1, md5, sha256):

```
$ curl -X POST -H 'Content-Type: application/json' --data \
     '{"sha1": "15ecf5c58e8749650d5fe5d641f77f3a0fffab16"}' \
     'https://libc.rip/api/find'
[
  {
    "buildid": "5ae879fe5a9ff3e6622cf0dbb19fc3a80b78ec9f",
    "download_url": "https://libc.rip/download/libc6_2.10.1-0ubuntu19_i386.so",
    "id": "libc6_2.10.1-0ubuntu19_i386",
    "md5": "8cf4746dab814f23cbc93aee208b19e3",
    "sha1": "15ecf5c58e8749650d5fe5d641f77f3a0fffab16",
    "sha256": "be5d51dbb3c96196b4b94ff04aa9cdd54fe80e3d3dd95cca1cf4d615c251ef5d",
    "symbols": {
      ...
    }
  }
]
```

Or a combination (combined via AND):

```
$ curl -X POST -H 'Content-Type: application/json' --data \
     '{"sha1": "15ecf5c58e8749650d5fe5d641f77f3a0fffab16", "buildid": "5ae879fe5a9ff3e6622cf0dbb19fc3a80b78ec9f", "symbols": {"dup2": "690", "puts": "2b0"}}' \
     'https://libc.rip/api/find'
[
  {
    "buildid": "5ae879fe5a9ff3e6622cf0dbb19fc3a80b78ec9f",
    "download_url": "https://libc.rip/download/libc6_2.10.1-0ubuntu19_i386.so",
    "id": "libc6_2.10.1-0ubuntu19_i386",
    "md5": "8cf4746dab814f23cbc93aee208b19e3",
    "sha1": "15ecf5c58e8749650d5fe5d641f77f3a0fffab16",
    "sha256": "be5d51dbb3c96196b4b94ff04aa9cdd54fe80e3d3dd95cca1cf4d615c251ef5d",
    "symbols": {
      ...
    }
  }
]
```


To dump a specific set of symbols, given the id of the library:

```
$ curl -X POST -H 'Content-Type: application/json' \
    --data '{"symbols": ["strcat"]}' \
    'https://libc.rip/api/libc/libc6_2.27-3ubuntu1.2_amd64'
{
  "buildid": "d3cf764b2f97ac3efe366ddd07ad902fb6928fd7",
  "download_url": "https://libc.rip/download/libc6_2.27-3ubuntu1.2_amd64.so",
  "id": "libc6_2.27-3ubuntu1.2_amd64",
  "md5": "35ef4ffc9c6ad7ffd1fd8c16f14dc766",
  "sha1": "a22321cd65f28f70cf321614fdfd22f36ecd0afe",
  "sha256": "f0ad9639b2530741046e06c96270b25da2339b6c15a7ae46de8fb021b3c4f529",
  "symbols": {
    "__libc_start_main_ret": "0x21b97",
    "dup2": "0x110ab0",
    "printf": "0x64f00",
    "puts": "0x80a30",
    "read": "0x110180",
    "str_bin_sh": "0x1b40fa",
    "strcat": "0x9d800",
    "system": "0x4f4e0",
    "write": "0x110250"
  }
}
```
