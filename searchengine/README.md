```
$ curl -X POST -H 'Content-Type: application/json' --data '{"symbols": {"strncpy": "db0", "strcat": "0x000000000d800"}}' 'https://libc.rip/api/find'
[
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
      "strncpy": "0x9ddb0",
      "system": "0x4f4e0",
      "write": "0x110250"
    }
  }
]

$ curl -X POST -H 'Content-Type: application/json' --data '{"symbols": ["strcat"]}' 'https://libc.rip/api/libc/libc6_2.27-3ubuntu1.2_amd64'
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
