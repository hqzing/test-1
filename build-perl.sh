#!/bin/sh
set -e

alpine_repository_url="http://dl-cdn.alpinelinux.org/alpine/v3.22/main/aarch64/"

download_alpine_index() {
    mkdir -p /opt/alpine-index
    cd /opt/alpine-index/
    curl -fsSL -O "${alpine_repository_url}/APKINDEX.tar.gz"
    tar -zxf APKINDEX.tar.gz
    cd - >/dev/null
}

get_apk_url() {
    package_name=$1
    version=$(grep -A 2 "^P:${package_name}$" /opt/alpine-index/APKINDEX | grep '^V:' | sed 's/^V://')
    apk_url="${alpine_repository_url}${package_name}-${version}.apk"
    echo $apk_url
}

query_component() {
  component=$1
  curl -fsSL 'https://ci.openharmony.cn/api/daily_build/build/list/component' \
    -H 'Accept: application/json, text/plain, */*' \
    -H 'Content-Type: application/json' \
    --data-raw '{"projectName":"openharmony","branch":"master","pageNum":1,"pageSize":10,"deviceLevel":"","component":"'${component}'","type":1,"startTime":"2025090100000000","endTime":"20990101235959","sortType":"","sortField":"","hardwareBoard":"","buildStatus":"success","buildFailReason":"","withDomain":1}'
}

# Set up the command-line tools needed for the build
download_alpine_index
curl -L -O $(get_apk_url busybox-static)
curl -L -O $(get_apk_url jq)
curl -L -O $(get_apk_url oniguruma)
curl -L -O $(get_apk_url make)
for file in *.apk; do
  tar -zxf $file -C /
done
rm -rf *.apk
rm /bin/xargs
ln -s /bin/busybox.static /bin/xargs
ln -s /bin/busybox.static /bin/tr
ln -s /bin/busybox.static /bin/expr
ln -s /bin/busybox.static /bin/awk
ln -s /bin/busybox.static /bin/unzip

# Setup ohos-sdk
sdk_ohos_download_url=$(query_component "ohos-sdk-public_ohos" | jq -r ".data.list.dataList[0].obsPath")
curl $sdk_ohos_download_url -o ohos-sdk-public_ohos.tar.gz
mkdir /opt/ohos-sdk
tar -zxf ohos-sdk-public_ohos.tar.gz -C /opt/ohos-sdk
cd /opt/ohos-sdk/ohos/
unzip -q native-*.zip
unzip -q toolchains-*.zip
cd - >/dev/null

# Build perl
export PATH=$PATH:/opt/ohos-sdk/ohos/native/llvm/bin
curl -L https://github.com/Perl/perl5/archive/refs/tags/v5.42.0.tar.gz -o perl5-5.42.0.tar.gz
tar -zxf perl5-5.42.0.tar.gz
cd perl5-5.42.0
sed -i 's/defined(__ANDROID__)/defined(__ANDROID__) || defined(__OHOS__)/g' perl_langinfo.h
./Configure \
    -des \
    -Dprefix=/opt/perl-5.42.0-ohos-arm64 \
    -Duserelocatableinc \
    -Dcc=clang \
    -Dcpp=clang++ \
    -Dar=llvm-ar \
    -Dnm=llvm-nm \
    -Accflags=-D_GNU_SOURCE
make -j$(nproc)
make install
cd ..

# Codesign
export PATH=$PATH:/opt/ohos-sdk/ohos/toolchains/lib
binary-sign-tool sign -inFile /opt/perl-5.42.0-ohos-arm64/bin/perl -outFile /opt/perl-5.42.0-ohos-arm64/bin/perl -selfSign 1
find /opt/perl-5.42.0-ohos-arm64/lib/ -type f | grep .so$ | xargs -I {} binary-sign-tool sign -inFile {} -outFile {} -selfSign 1

# Copy the license into the release artifacts
cp perl5-5.42.0/Copying /opt/perl-5.42.0-ohos-arm64
cp perl5-5.42.0/AUTHORS /opt/perl-5.42.0-ohos-arm64

cd /opt/
tar -zcf perl-5.42.0-ohos-arm64.tar.gz perl-5.42.0-ohos-arm64
