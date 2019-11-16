#!/usr/bin/env bash
#This is free and unencumbered software released into the public domain.
#
#Anyone is free to copy, modify, publish, use, compile, sell, or
#distribute this software, either in source code form or as a compiled
#binary, for any purpose, commercial or non-commercial, and by any
#means.
#
#In jurisdictions that recognize copyright laws, the author or authors
#of this software dedicate any and all copyright interest in the
#software to the public domain. We make this dedication for the benefit
#of the public at large and to the detriment of our heirs and
#successors. We intend this dedication to be an overt act of
#relinquishment in perpetuity of all present and future rights to this
#software under copyright law.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
#MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
#OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
#ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#OTHER DEALINGS IN THE SOFTWARE.
#
#For more information, please refer to <http://unlicense.org/>
#
# usage: verify-kafka-rc.sh VERSION REMOTE_RELEASE_SITE
# example: ./verify-kafka-rc.sh 2.2.2 https://home.apache.org/~rhauch/kafka-2.2.2-rc2
#
# lightly tested on os x.

set -e
set -u
set -o pipefail

if [ $# -ne 2 ]; then
    echo "usage:"
    echo -e "\tverify-kafka-rc.sh VERSION REMOTE_RELEASE_SITE"
    echo "example:"
    echo "verify-kafka-rc.sh 2.2.2 home.apache.org/~rhauch/kafka-2.2.2-rc2"
    exit 1
fi

set +e
for x in wget gpg md5sum sha1sum sha512sum tr cut tar gradle sed; do
    which $x >/dev/null
    if [ $? -ne 0 ]; then
        echo "missing required utility $x">&2
        exit 1;
    fi
done
set -e 

declare -r KEYS_URL='https://kafka.apache.org/KEYS'
declare -r WORKDIR="$TMPDIR/$$.out"
declare -r KEYS_FILE="$WORKDIR/keys.out"
declare -r VERSION="$1"
declare -r REMOTE_RELEASE_SITE="$2"
declare -r FILES=RELEASE_NOTES.html\ kafka-$VERSION-src.tgz\ kafka_2.11-$VERSION-site-docs.tgz\ kafka_2.11-$VERSION.tgz\ kafka_2.12-$VERSION-site-docs.tgz\ kafka_2.12-$VERSION.tgz

mkdir -p $WORKDIR

echo "workdir: $WORKDIR"
echo "Downloading signing keys"
wget -q $KEYS_URL -O $KEYS_FILE

echo "Importing signing keys"
gpg --import "$KEYS_FILE"

echo "Downloading release files"
for x in $FILES; do
    echo -e "\t$x"
    wget -q $REMOTE_RELEASE_SITE/$x -O $WORKDIR/$x
    for y in asc md5 sha1 sha512; do
        echo -e "\t$x.$y"
        wget -q $REMOTE_RELEASE_SITE/$x.$y -O $WORKDIR/$x.$y
    done
done

echo "Verifying pgp signatures"
for x in $FILES; do
    gpg --verify $WORKDIR/$x.asc
done

for x in md5 sha1 sha512; do
    util=${x}sum
    echo "Verifying ${x}sums"
    for y in $FILES; do
        sum=$(cat $WORKDIR/$y.$x | tr -d '\n' | cut -d':' -f2- | sed -e 's/ //g')
        echo "$sum $WORKDIR/$y" >$WORKDIR/$y.$x.normalized
        $util -c $WORKDIR/$y.$x.normalized
    done
done

echo "Verifying kafka source tree"
pushd $WORKDIR >/dev/null
tar zxf kafka-$VERSION-src.tgz
pushd $WORKDIR/kafka-$VERSION-src >/dev/null
echo -e "Invoking gradle"
gradle
for x in srcJar javadoc javadocJar scaladoc scaladocJar docsjar unitTest integrationTest; do
    echo -e "\tBuilding $x"
    ./gradlew $x
done
popd >/dev/null
popd >/dev/null
echo "All steps successful."
