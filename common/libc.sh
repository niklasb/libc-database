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
  local lib=$1
  local id=$2
  local info=$3
  local url=$4
  local suffix=$5
  echo "  -> Writing binary $lib to db/${id}/"
  mkdir -p db/${id}/
  cp $lib db/${id}/$(basename $lib)$suffix
  echo "  -> Writing symbols to db/${id}/"

  (dump_symbols $lib; dump_libc_start_main_ret $lib; dump_bin_sh $lib)  > db/${id}/"$(basename $lib)$suffix".symbols

  [[ -f "db/${id}/info" ]] && return

  echo "  -> Writing version info"
  echo "$info" > db/${id}/info
  echo "$url" > db/${id}/url
}

process_debug() {
  local lib=$1
  local id=$2
  local suffix=$3

  echo "  -> Writing libc debug symbols to db/${id}/.debug/"
  mkdir -p db/${id}/.debug
  cp $lib db/${id}/.debug/$(basename $lib)$suffix
}

index_libc() {
  local tmp="$1"
  local id="$2"
  local info="$3"
  local url="$4"
  # Sometimes, the real libc.so is not matched with `libc.so*`.
  libs=$(find "$tmp" -name '*.so*' | grep -v ".conf")
  declare -A dejavu
  [[ -z "$libs" ]] && die "Cannot locate any library file"
  for lib in $libs; do
    # Some file matched can be ASCII files instead :(
    if ! (file "$lib" | grep -q 'ELF\|symbolic link to') ; then
      echo "  -> library ${lib} is not an ELF file"
      continue  # Keep cnt and suffix as it
    fi
	[[ -z ${dejavu[$lib]} ]] && dejavu[$lib]=$((0))
	process_libc "$lib" "$id" "$info" "$url" "${dejavu[$lib]}"
	dejavu[$lib]=$((${dejavu[$lib]}+1))
  done
}

index_debug() {
  local tmp="$1"
  local id="$2"
  libs=$(find "$tmp" -name '*.so*' | grep -v ".conf")
  # Usually, find's order is the same as libc one.
  declare -A dejavu
  if [[ -z "$libs" ]]; then
    echo "  -> Cannot locate any debug file. Skipping"
	return
  fi
  for lib in $libs; do
  	[[ -z ${dejavu[$lib]} ]] && dejavu[$lib]=$((0))
  	process_debug "$lib" "$id" "${dejavu[$lib]}"
	dejavu[$lib]=$((${dejavu[$lib]}+1))
  done
}

check_id() {
  local id=$1
  if [[ -d db/${id} ]]; then
    echo "  -> Already have this version, 'rm -rf ${PWD}/db/${id}' to force"
    return 1
  fi
  return 0
}

requirements_general() {
  which readelf  1>/dev/null 2>&1 || return
  which perl     1>/dev/null 2>&1 || return
  which objdump  1>/dev/null 2>&1 || return
  which strings  1>/dev/null 2>&1 || return
  which find     1>/dev/null 2>&1 || return
  which grep     1>/dev/null 2>&1 || return
  which basename 1>/dev/null 2>&1 || return
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

get_debian_debug_symbols() {
  local url=$1
  local origin=$2
  local info=$3
  local pkgname=$4
  local tmp=`mktemp -d`
  echo "Getting debug symbols of $info"
  echo "  -> Location: $url"
  local id=`echo $origin | perl -n -e '/('"$pkgname"'[^\/]*)\./ && print $1'`
  echo "  -> ID: $id"
  echo "  -> Downloading debug symbol"
  if ! wget "$url" 2>/dev/null -O $tmp/pkg.deb; then
    echo >&2 "Failed to download debug symbol from $url. Skipping"
	return
  fi
  echo "  -> Extracting debug symbol"
  pushd $tmp 1>/dev/null
  if ! ar x pkg.deb; then
    echo >&2"ar failed. Skipping"
	return
  fi
  if [ -f data.tar.zst ]; then
    if ! zstd -d data.tar.zst; then
	  echo >&2 "zstd failed. Skipping"
	  return
	fi
    if ! tar xf data.tar; then
	  echo >&2 "tar failed, Skipping"
	  return
	fi
  else
    if ! tar xf data.tar.*; then
	  echo >&2 "tar failed, Skipping"
	  return
	fi
  fi
  popd 1>/dev/null
  index_debug $tmp $id
}

get_all_debian() {
  local info=$1
  local url=$2
  local pkgname=$3
  for f in `wget $url/ -O - 2>/dev/null | grep -Eoh "$pkgname"'(-i386|-amd64|-x32)?_[^"]*(amd64|i386)\.deb' |grep -v "</a>"`; do
    get_debian "$url/$f" "$info" "$pkgname"
    local debugfile=$(echo $f | sed -r "s/$pkgname'(-i386|-amd64|-x32)?'/$pkgname-dbg/g")
	get_debian_debug_symbols "$url/$debugfile" "$url/$f" "$info" "$pkgname"
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
  which sed    1>/dev/null 2>&1 || return
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

get_rpm_debug_symbols() {
  local url="$1"
  [[ -z $(echo "$url" | sed -r "s/\s*$//g" | sed -r "s/^\s*//g" ) ]] && return
  local origin="$2"
  local info="$3"
  local pkgname="$4"
  local tmp="$(mktemp -d)"
  echo "Getting debug symbols of $info"
  echo "  -> Location: $url"
  local id=$(echo "$origin" | perl -n -e '/('"$pkgname"'[^\/]*)\./ && print $1')
  echo "  -> ID: $id"
  echo "  -> Downloading debug symbol"
  if ! wget --no-dns-cache --connect-timeout=30 "$url" 2>/dev/null -O "$tmp/pkg.rpm"; then
    echo >&2 "Failed to download debug symbol from $url. It seems that $id does not have a debug symbol. Do not worry"
	return
  fi
  echo "  -> Extracting debug symbol"
  pushd "$tmp" 1>/dev/null
  rpm2cpio pkg.rpm | cpio -id --quiet
  popd 1>/dev/null
  index_debug "$tmp" "$id"
  rm -rf "$tmp"
}

get_all_rpm() {
  local info=$1
  local pkg=$2
  local pkgdebug=$pkg-debuginfo
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
  local debugsearchurl="$website/linux/rpm2html/search.php?query=$pkgdebug"
  echo "Getting debug RPM package location: $info $pkgdebug $pkgname $arch"
  for i in $(seq 1 3); do
    dbgurls=$(wget "$debugsearchurl" -O - 2>/dev/null \
	  | grep -oh "/[^']*${pkgname}[^']*\.$arch\.rpm")
	[[ -z "$dbgurls" ]] || break
	echo "Retrying..."
	sleep 1
  done

  if ! [[ -n "$urls" ]]; then
    echo >&2 "Failed to get RPM package URL for $info $pkg $pkgname $arch"
    return
  fi
  declare -A rpmdebugs
  if [[ -n "$dbgurls" ]]; then
    echo "Building rpm & debug package mappings"
    for original in $urls; do
	  local currentpkgname=$(basename $original)
	  local debugpkgname=$(echo $currentpkgname | sed 's/'$pkg'/'$pkgdebug'/g')
	  for debug in $dbgurls; do
	    if [[ -z $(echo $debug | grep "$debugpkgname") ]]; then
		  continue
		fi
		rpmdebugs[$original]=$website$debug
	  done
	done
  fi

  for url in $urls
  do
    get_rpm "$website$url" "$info" "$pkgname"
	get_rpm_debug_symbols "${rpmdebugs[$url]}" "$website$url" "$info" "$pkgname"
    sleep .1
  done
}

requirements_rpm() {
  which mktemp   1>/dev/null 2>&1 || return
  which perl     1>/dev/null 2>&1 || return
  which wget     1>/dev/null 2>&1 || return
  which rpm2cpio 1>/dev/null 2>&1 || return
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
  local debugwebsite=$5
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
	local slices=(${url//\// })
	local systemver=${slices[1]}
	local verslices=(${systemver//\./ })
	local major=${verslices[0]}
	echo $major

	local debugname=$(echo $url | sed "s/glibc/glibc-debuginfo/g" | sed -r "s/[0-9]+\.[0-9]+\.[0-9]+/$major/g" | sed "s/\/os//g" | sed "s/\/Packages//g")
	echo $debugname
	get_rpm_debug_symbols "$debugwebsite/$debugname" "$website/$url" "$info" "$pkg"
    sleep .1
  done
}

requirements_centos() {
  which wget       1>/dev/null 2>&1 || return
  which gzip       1>/dev/null 2>&1 || return
  which grep       1>/dev/null 2>&1 || return
  which sed        1>/dev/null 2>&1 || return
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

get_pkg_debug() {
  local info=$1
  local original=$2
  local pkgname=$3
  local debugname=$4
  local tmp="$(mktemp -d)"
  echo "Getting debug symbol of "$pkgname

  local id=$(echo "$original" | perl -n -e '/('"$pkgname"'[^\/]*)\.pkg\.tar\.(xz|zst)/ && print $1' | ( (echo "$original" | grep -q 'lib32') && sed 's/x86_64/x86/g' || cat))
  local idslices=(${id//\-/ })
  local version=${idslices[1]}
  local pkgrel=${idslices[2]}
  local arch=${idslices[3]}

  pushd $tmp 1>/dev/null
  # https://github.com/pwndbg/pwndbg/issues/340#issuecomment-431254792
  echo "  -> Initializing svn repository"
  if ! svn checkout --depth=empty svn://svn.archlinux.org/packages pkgs 1>/dev/null 2>&1; then
    echo >&2 "Could not initialize the svn repository. Skipping"
	popd 1>/dev/null
	return
  fi
  pushd pkgs 1>/dev/null
  if ! svn update $debugname 1>/dev/null 2>&1; then
    echo >&2 "Could not checkout "$debugname". Skipping"
	popd 1>/dev/null
	popd 1>/dev/null
	return
  fi

  pushd $debugname/repos/core-x86_64 1>/dev/null
  echo "  -> Checking version"
  local repoverraw=$(cat PKGBUILD | grep "pkgver")
  local repoverslices=(${repoverraw//\=/ })
  local repover=${repoverslices[1]}

  local repopkgrelraw=$(cat PKGBUILD | grep "pkgrel")
  local repopkgrelslices=(${repopkgrelraw//\=/ })
  local repopkgrel=${repopkgrelslices[1]}

  if [[ "$repover" != "$version" || "$pkgrel" != "$repopkgrel" ]] ; then
    echo "  -> Version mismatches, package one is $version-$pkgrel and the other one is $repover-$repopkgrel. Skipping"
	popd 1>/dev/null
	popd 1>/dev/null
	return
  fi
  
  echo "  -> Replacing PKGBUILD file"
  if ! sed -i "s#!strip#debug#" PKGBUILD 1>/dev/null 2>&1; then
    echo >&2 "Could not replace PKGBUILD file. Skipping"
  fi
  echo "  -> Started building $id"
  if ! makepkg --skipchecksums --nocheck 1>/dev/null 2>&1; then
    echo >&2 "Could not build $id. Skipping"
    popd 1>/dev/null
    popd 1>/dev/null
    popd 1>/dev/null
	return
  fi
  echo "  -> Cleaning up the work environment"
  find . -type d -exec rm -rf {} \; 1>/dev/null 2>&1
  echo "  -> Extracting built package"
  local debugpkg=$(ls | grep "debug" | grep ".tar.")
  if (echo "$debugpkg" | grep -q '\.zst')
  then
    zstd -dq $debugpkg -o pkg.tar
    tar xf pkg.tar --warning=none
  fi
  if (echo "$url" | grep -q '\.xz')
  then
    tar xJf $debugpkg --warning=none
  fi

  echo "  -> Removing unneeded symbols"
  if grep -q "x86_64" <<< "$arch"; then
    find usr/lib/debug -name "lib32" -type d -exec rm -rf {} \; 1>/dev/null 2>&1
  else
    find usr/lib/debug -name "lib" -type d -exec rm {} \; 1>/dev/null 2>&1
  fi

  popd 1>/dev/null
  popd 1>/dev/null
  popd 1>/dev/null

  index_debug $tmp $id
  rm -rf $tmp
}

get_all_pkg() {
  local info=$1
  local directory=$2
  local pkgname=$3
  local debugname=$4
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
	[[ -z $debugname ]] && die 1
	get_pkg_debug "$info" "$directory/$url" "$pkgname" "$debugname"
	sleep 1
  done
}

requirements_pkg() {
  which mktemp  1>/dev/null 2>&1 || return
  which perl    1>/dev/null 2>&1 || return
  which grep    1>/dev/null 2>&1 || return
  which sed     1>/dev/null 2>&1 || return
  which cat     1>/dev/null 2>&1 || return
  which wget    1>/dev/null 2>&1 || return
  which zstd    1>/dev/null 2>&1 || return
  which tar     1>/dev/null 2>&1 || return
  which xz      1>/dev/null 2>&1 || return
  which svn     1>/dev/null 2>&1 || return
  which makepkg 1>/dev/null 2>&1 || return
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

get_apk_debug() {
  local url=$1
  local original=$2
  local info="$2"229
  local pkgname="$3"
  local tmp=$(mktemp -d)

  echo "Getting debug symbols of $info"
  echo "  -> Location: $url"
  local id=$(echo "$original" | perl -n -e '/('"$pkgname"'[^\/]*)\.apk/ && print $1')
  echo "  -> ID: $id"
  echo "  -> Downloading debug symbol"
  if ! wget "$url" 2>/dev/null -O "$tmp/pkg.tar.gz"; then
    echo >&2 "Failed to download debug symbol from $url. Skipping"
	return
  fi
  echo "  -> Extracting debug symbol"
  pushd $tmp 1>/dev/null
  tar xzf pkg.tar.gz --warning=none
  popd 1>/dev/null
  index_debug "$tmp" "$id"
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
	local debugurl=$(echo $f | sed -r "s/$pkgname/$pkgname-dbg/g")
	get_apk_debug "$directory$debugurl" "$directory$url" "$info" "$pkgname"
    sleep .1
  done
}

requirements_apk() {
  which mktemp 1>/dev/null 2>&1 || return
  which perl   1>/dev/null 2>&1 || return
  which wget   1>/dev/null 2>&1 || return
  which tar    1>/dev/null 2>&1 || return
  which gzip   1>/dev/null 2>&1 || return
  which grep   1>/dev/null 2>&1 || return
  which sed    1>/dev/null 2>&1 || return
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
	local dbgurl=""
    urls=$(wget "$apiurl" -O - 2>/dev/null | jq '[ .entries[] | .build_link + "/+files/" + .binary_package_name + "_" + .source_package_version + "_" + (.distro_arch_series_link | split("/") | .[-1]) + ".deb" | ltrimstr("https://api.launchpad.net/1.0/") | "https://launchpad.net/" + . ] | unique | .[]')
    for url in $urls; do
      url=$(echo $url | grep -Eo '[^"]+')
      # some old packages are deleted. ignore those.
      get_debian "$url" "$info-$series" "$pkgname"
	  dbgurl=$(echo $url | sed "s/$pkgname/$pkgname-dbg/g")
	  get_debian_debug_symbols "$dbgurl" "$url" "$info-$series" "$pkgname"
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

