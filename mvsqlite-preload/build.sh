#!/bin/sh

CURRENT_DIR=$PWD
# locate
if [ -z "$BASH_SOURCE" ]; then
    SCRIPT_DIR=`dirname "$(readlink -f $0)"`
elif [ -e '/bin/zsh' ]; then
    F=`/bin/zsh -c "print -lr -- $BASH_SOURCE(:A)"`
    SCRIPT_DIR=`dirname $F`
elif [ -e '/usr/bin/realpath' ]; then
    F=`/usr/bin/realpath $BASH_SOURCE`
    SCRIPT_DIR=`dirname $F`
else
    F=$BASH_SOURCE
    while [ -h "$F" ]; do F="$(readlink $F)"; done
    SCRIPT_DIR=`dirname $F`
fi
# change pwd
cd $SCRIPT_DIR

SQLITE_RELEASE_YEAR='2023'
SQLITE_VERSION='3410000'

export PKG_CONFIG_PATH=/opt/target/openssl/lib/pkgconfig
export CFLAGS='-O2 -fPIC'
EXTRA_FLAGS=''

UNAME=`uname`
case "$UNAME" in
    Darwin)
    EXTRA_FLAGS='-framework Security'
    ;;
    Linux)
    EXTRA_FLAGS='-Wl,-z,noexecstack'
    ;;
esac

dl_to_dir() {
  cd $1
  curl -LO $2
  cd - > /dev/null
}

build_preload() {
clang -O2 -shared $EXTRA_FLAGS \
-o libmvsqlite_preload.so \
preload.o shim.o \
-L/opt/target/openssl/lib \
-L../target/release \
-lmvsqlite -lsqlite3 -lssl -lcrypto -lpthread -ldl -lm
}

build_lib() {
ar rcs libmvsqlite.a shim.o
}

build_patched_sqlite3() {
clang -O2 -fPIC -shared $EXTRA_FLAGS \
-o libsqlite3.so \
-DSQLITE_ENABLE_FTS3 \
-DSQLITE_ENABLE_FTS4 \
-DSQLITE_ENABLE_FTS5 \
-DSQLITE_ENABLE_RTREE \
-DSQLITE_ENABLE_DBSTAT_VTAB \
-DSQLITE_ENABLE_MATH_FUNCTIONS \
-DSQLITE_ENABLE_COLUMN_METADATA \
-DMV_STATIC_PATCH \
-I./target/src \
./target/src/sqlite3.c ./preload.c ./shim.c \
-L/opt/target/openssl/lib \
-L../target/release \
-lmvsqlite -lpthread -ldl -lm
}

patch_and_link() {
  cd "target/sqlite-amalgamation-$SQLITE_VERSION"
  patch < "../../sqlite-$SQLITE_VERSION.patch" && \
  cd .. && \
  ln -s "sqlite-amalgamation-$SQLITE_VERSION" src && \
  cd ..
}

extract_sqlite_zip() {
  cd target
  unzip "sqlite-amalgamation-$SQLITE_VERSION.zip"
  cd ..
}

mkdir -p target
[ -e "target/sqlite-amalgamation-$SQLITE_VERSION.zip" ] || dl_to_dir target "https://www.sqlite.org/$SQLITE_RELEASE_YEAR/sqlite-amalgamation-$SQLITE_VERSION.zip"
[ -e "target/sqlite-amalgamation-$SQLITE_VERSION" ] || extract_sqlite_zip
[ -e target/src ] || patch_and_link || { echo 'Patch failed.'; exit 1; }

echo 'Building ...'
build_patched_sqlite3 && \
build_preload && \
build_lib && \
echo 'Build sucessful!'
