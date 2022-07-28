#!/bin/bash

mkdir -p db

die() {
  echo >&2 $1
  exit 1
}

dump_symbols() {
  readelf -Ws $1 | perl -n -e '/: (\w+)\s+\w+\s+(?:FUNC|OBJECT)\s+(?:\w+\s+){3}(\w+)\b(?:@@GLIBC)?/ && print "$2 $1\n"' | sort -u
}

extract_label() {
  perl -n -e '/(\w+)/ && print $1'
}

dump_libc_start_main_ret() {
  local call_main=`objdump -D $1 \
    | grep -EA 100 '<__libc_start_main.*>:' \
    | grep call \
    | grep -EB 1 '<exit.*>' \
    | head -n 1 \
    | extract_label`
  # Since glibc 2.34 it's __libc_start_main -> __libc_start_call_main -> main
  # and __libc_start_call_main is right before __libc_start_main.
  if [[ "$call_main" == "" ]]; then
    local call_main=`objdump -D $1 \
      | grep -EB 100 '<__libc_start_main.*>:' \
      | grep call \
      | grep -EB 1 '<exit.*>' \
      | head -n 1 \
      | extract_label`
  fi
  local offset=`objdump -D $1 | grep -EA 1 "(^| )$call_main:" | tail -n 1 | extract_label`
  if [[ "$offset" != "" ]]; then
    echo "__libc_start_main_ret $offset"
  fi
}

dump_bin_sh() {
  local offset=`strings -a -t x $1 | grep '/bin/sh' | head -n1 | extract_label`
  if [[ "$offset" != "" ]]; then
    echo "str_bin_sh $offset"
  fi
}

process_libc() {
  local libc=$1
  local id=$2
  local info=$3
  local url=$4
  echo "  -> Writing libc ${libc} to db/${id}.so"
  cp $libc db/${id}.so
  echo "  -> Writing symbols to db/${id}.symbols"
  (dump_symbols $libc; dump_libc_start_main_ret $libc; dump_bin_sh $libc) \
     > db/${id}.symbols
  echo "  -> Writing version info"
  echo "$info" > db/${id}.info
  echo "$url" > db/${id}.url
}

index_libc() {
  local tmp="$1"
  local id="$2"
  local info="$3"
  local url="$4"
  suffix=
  cnt=1
  # Sometimes, the real libc.so is not matched with `libc.so*`.
  libs=$(find "$tmp" -name 'libc.so*';find "$tmp" -name 'libc[-_.][a-z]*.so*')
  [[ -z "$libs" ]] && die "Cannot locate the libc file"
  for libc in $libs; do
    # Some file matched can be ASCII files instead :(
    if ! (file "$libc" | grep -q 'ELF\|symbolic link to') ; then
      echo "  -> libc ${libc} is not an ELF file"
      continue  # Keep cnt and suffix as it
    fi
    process_libc "$libc" "$id$suffix" "$info" "$url"
    cnt=$((cnt+1))
    suffix=_$cnt
  done
}

check_id() {
  local id=$1
  if [[ -e db/${id}.info ]]; then
    echo "  -> Already have this version, 'rm ${PWD}/db/${id}.*' to force"
    return 1
  fi
  return 0
}

requirements_general() {
  which readelf 1>/dev/null 2>&1 || return
  which perl    1>/dev/null 2>&1 || return
  which objdump 1>/dev/null 2>&1 || return
  which strings 1>/dev/null 2>&1 || return
  which find    1>/dev/null 2>&1 || return
  which grep    1>/dev/null 2>&1 || return
  return 0
}

# ===== Debian-like ===== #

get_debian() {
  local url="$1"
  local info="$2"
  local pkgname="$3"
  local tmp=`mktemp -d`
  echo "Getting $info"
  echo "  -> Location: $url"
  local id=`echo $url | perl -n -e '/('"$pkgname"'[^\/]*)\./ && print $1'`
  echo "  -> ID: $id"
  check_id $id || return
  echo "  -> Downloading package"
  if ! wget "$url" 2>/dev/null -O $tmp/pkg.deb; then
    echo >&2 "Failed to download package from $url"
    return
  fi
  echo "  -> Extracting package"
  pushd $tmp 1>/dev/null
  ar x pkg.deb || die "ar failed"
  if [ -f data.tar.zst ]; then
    zstd -d data.tar.zst || die "zstd failed"
    tar xf data.tar || die "tar failed"
  else
    tar xf data.tar.* || die "tar failed"
  fi
  popd 1>/dev/null
  index_libc "$tmp" "$id" "$info" "$url"
  rm -rf $tmp
}

get_all_debian() {
  local info=$1
  local url=$2
  local pkgname=$3
  for f in `wget $url/ -O - 2>/dev/null | grep -Eoh "$pkgname"'(-i386|-amd64|-x32)?_[^"]*(amd64|i386)\.deb' |grep -v "</a>"`; do
    get_debian "$url/$f" "$info" "$pkgname"
  done
  return 0
}

requirements_debian() {
  which mktemp 1>/dev/null 2>&1 || return
  which perl   1>/dev/null 2>&1 || return
  which wget   1>/dev/null 2>&1 || return
  which ar     1>/dev/null 2>&1 || return
  which tar    1>/dev/null 2>&1 || return
  which grep   1>/dev/null 2>&1 || return
  which zstd   1>/dev/null 2>&1 || return
  return 0
}

# ===== RPM ===== #

get_rpm() {
  local url="$1"
  local info="$2"
  local pkgname="$3"
  local tmp="$(mktemp -d)"
  echo "Getting $info"
  echo "  -> Location: $url"
  local id=$(echo "$url" | perl -n -e '/('"$pkgname"'[^\/]*)\./ && print $1')
  echo "  -> ID: $id"
  check_id "$id" || return
  echo "  -> Downloading package"
  if ! wget --no-dns-cache --connect-timeout=30 "$url" 2>/dev/null -O "$tmp/pkg.rpm"; then
    echo >&2 "Failed to download package from $url"
    return
  fi
  echo "  -> Extracting package"
  pushd "$tmp" 1>/dev/null
  (rpm2cpio pkg.rpm || die "rpm2cpio failed") | \
    (cpio -id --quiet || die "cpio failed")
  popd 1>/dev/null
  index_libc "$tmp" "$id" "$info" "$url"
  rm -rf "$tmp"
}

get_all_rpm() {
  local info=$1
  local pkg=$2
  local pkgname=$3
  local arch=$4
  local website="http://rpmfind.net"
  local searchurl="$website/linux/rpm2html/search.php?query=$pkg"
  echo "Getting RPM package location: $info $pkg $pkgname $arch"
  local url=""
  for i in $(seq 1 3); do
    urls=$(wget "$searchurl" -O - 2>/dev/null \
      | grep -oh "/[^']*${pkgname}[^']*\.$arch\.rpm")
    [[ -z "$urls" ]] || break
    echo "Retrying..."
    sleep 1
  done

  if ! [[ -n "$urls" ]]; then
    echo >&2 "Failed to get RPM package URL for $info $pkg $pkgname $arch"
    return
  fi

  for url in $urls
  do
    get_rpm "$website$url" "$info" "$pkgname"
    sleep .1
  done
}

requirements_rpm() {
  which mktemp   1>/dev/null 2>&1 || return
  which perl     1>/dev/null 2>&1 || return
  which wget     1>/dev/null 2>&1 || return
  which rpm2cpio || return
  which cpio     1>/dev/null 2>&1 || return
  which grep     1>/dev/null 2>&1 || return
  return 0
}

# ===== CentOS ===== #

get_from_filelistgz() {
  local info=$1
  local website=$2
  local pkg=$3
  local arch=$4
  echo "Getting package $pkg locations"
  local url=""
  for i in $(seq 1 3); do
    urls=$(wget "$website/filelist.gz" -O - 2>/dev/null \
      | gzip -cd \
      | grep -h "$pkg-[0-9]" \
      | grep -h "$arch\.rpm")
    [[ -z "$urls" ]] || break
    echo "Retrying..."
    sleep 1
  done
  [[ -n "$urls" ]] || die "Failed to get package version"
  for url in $urls
  do
    get_rpm "$website/$url" "$info" "$pkg"
    sleep .1
  done
}

requirements_centos() {
  which wget       1>/dev/null 2>&1 || return
  which gzip       1>/dev/null 2>&1 || return
  which grep       1>/dev/null 2>&1 || return
  requirements_rpm || return
  return 0
}


# ===== Arch ===== #

get_pkg() {
  local url="$1"
  local info="$2"
  local pkgname="$3"
  local tmp="$(mktemp -d)"
  echo "Getting $info"
  echo "  -> Location: $url"
  local id=$(echo "$url" | perl -n -e '/('"$pkgname"'[^\/]*)\.pkg\.tar\.(xz|zst)/ && print $1' | ( (echo "$url" | grep -q 'lib32') && sed 's/x86_64/x86/g' || cat))
  echo "  -> ID: $id"
  check_id $id || return
  echo "  -> Downloading package"
  if ! wget "$url" 2>/dev/null -O "$tmp/pkg"; then
    echo >&2 "Failed to download package from $url"
    return
  fi
  echo "  -> Extracting package"
  pushd "$tmp" 1>/dev/null
  if (echo "$url" | grep -q '\.zst')
  then
    mv pkg pkg.tar.zst
    zstd -dq pkg.tar.zst
    tar xf pkg.tar --warning=none
  fi
  if (echo "$url" | grep -q '\.xz')
  then
    mv pkg pkg.tar.xz
    tar xJf pkg.tar.xz --warning=none
  fi
  popd 1>/dev/null
  index_libc "$tmp" "$id" "$info" "$url"
  rm -rf "$tmp"
}

get_all_pkg() {
  local info=$1
  local directory=$2
  local pkgname=$3
  echo "Getting package $info locations"
  local url=""
  for i in $(seq 1 3); do
    urls=$(wget "$directory" -O - 2>/dev/null \
      | grep -oh '[^"]*'"$pkgname"'[^"]*\.pkg[^"]*' \
      | grep -v '.sig' \
      | grep -v '>')
    [[ -z "$urls" ]] || break
    echo "Retrying..."
    sleep 1
  done
  [[ -n "$urls" ]] || die "Failed to get package version"
  for url in $urls
  do
    get_pkg "$directory/$url" "$info" "$pkgname"
    sleep .1
  done
}

requirements_pkg() {
  which mktemp 1>/dev/null 2>&1 || return
  which perl   1>/dev/null 2>&1 || return
  which grep   1>/dev/null 2>&1 || return
  which sed    1>/dev/null 2>&1 || return
  which cat    1>/dev/null 2>&1 || return
  which wget   1>/dev/null 2>&1 || return
  which zstd   1>/dev/null 2>&1 || return
  which tar    1>/dev/null 2>&1 || return
  which xz     1>/dev/null 2>&1 || return
  return 0
}


# ===== Alpine ===== #

get_apk() {
  local url="$1"
  local info="$2"229
  local pkgname="$3"
  local tmp=$(mktemp -d)
  echo "Getting $info"
  echo "  -> Location: $url"
  local id=$(echo "$url" | perl -n -e '/('"$pkgname"'[^\/]*)\.apk/ && print $1')
  echo "  -> ID: $id"
  check_id $id || return
  echo "  -> Downloading package"
  if ! wget "$url" 2>/dev/null -O "$tmp/pkg.tar.gz"; then
    echo >&2 "Failed to download package from $url"
    return
  fi
  echo "  -> Extracting package"
  pushd $tmp 1>/dev/null
  tar xzf pkg.tar.gz --warning=none
  popd 1>/dev/null
  index_libc "$tmp" "$id" "$info" "$url"
  rm -rf $tmp
}

get_all_apk() {
  local info=$1
  local repo=$2
  local version=$3
  local component=$4
  local arch=$5
  local pkgname=$6
  local directory="$repo/$version/$component/$arch/"
  echo "Getting package $info locations"
  local url=""
  for i in $(seq 1 3); do
    urls=$(wget "$directory" -O - 2>/dev/null \
      | grep -oh '[^"]*'"$pkgname"'-[0-9][^"]*\.apk' \
      | grep -v '.sig' \
      | grep -v '>')
    [[ -z "$urls" ]] || break
    echo "Retrying..."
    sleep 1
  done
  [[ -n "$urls" ]] || die "Failed to get package version"
  for url in $urls
  do
    get_apk "$directory$url" "$info" "$pkgname"
    sleep .1
  done
}

requirements_apk() {
  which mktemp 1>/dev/null 2>&1 || return
  which perl   1>/dev/null 2>&1 || return
  which wget   1>/dev/null 2>&1 || return
  which tar    1>/dev/null 2>&1 || return
  which gzip    1>/dev/null 2>&1 || return
  which grep   1>/dev/null 2>&1 || return
  return 0
}

# ===== Launchpad =====

get_all_launchpad() {
  local info="$1"
  local distro="$2"
  local pkgname="$3"
  local arch="$4"

  local series=""
  for series in $(wget "https://api.launchpad.net/1.0/$distro/series" -O - 2>/dev/null | jq '.entries[] | .name'); do
    series=$(echo $series | grep -Eo '[^"]+')
    echo "Launchpad: Series $series"
    local apiurl="https://api.launchpad.net/1.0/$distro/+archive/primary?ws.op=getPublishedBinaries&binary_name=$pkgname&exact_match=true&distro_arch_series=https://api.launchpad.net/1.0/$distro/$series/$arch"
    local url=""
    urls=$(wget "$apiurl" -O - 2>/dev/null | jq '[ .entries[] | .build_link + "/+files/" + .binary_package_name + "_" + .source_package_version + "_" + (.distro_arch_series_link | split("/") | .[-1]) + ".deb" | ltrimstr("https://api.launchpad.net/1.0/") | "https://launchpad.net/" + . ] | unique | .[]')
    for url in $urls; do
      url=$(echo $url | grep -Eo '[^"]+')
      # some old packages are deleted. ignore those.
      get_debian "$url" "$info-$series" "$pkgname"
    done
  done
}

requirements_launchpad() {
  which jq       1>/dev/null 2>&1 || return
  requirements_debian || return
  return 0
}

# ===== Local ===== #

add_local() {
  local libc=$1
  [[ -f $libc ]] || return
  local info="local"
  local id="local-`sha1sum $libc`"
  echo "Adding local libc $libc (id $id)"
  check_id $id || return
  process_libc $libc $id $info
}

requirements_local() {
  which sha1sum 1>/dev/null 2>&1 || return
  return 0
}
