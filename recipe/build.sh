#!/bin/bash

set -e # Abort on error.

# TEST 6/25/2021
#pushd build-aux
# rm config.guess
# curl -o config.guess ‘https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD’
# rm config.sub
# curl -o config.sub ‘https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD’
#popd


export PING_SLEEP=30s
export WORKDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export BUILD_OUTPUT=$WORKDIR/build.out

touch $BUILD_OUTPUT

dump_output() {
   echo Tailing the last 500 lines of output:
   tail -500 $BUILD_OUTPUT
}

# Set up a repeating loop to send some output to Travis.
bash -c "while true; do echo \$(date) - building ...; sleep $PING_SLEEP; done" &
PING_LOOP_PID=$!

error_handler() {
  echo ERROR: An error was encountered with the build.
  # remember to kill our pinger, else it continues sending output ad infinitum  
  kill $PING_LOOP_PID
  dump_output
  exit 1
}

# If an error occurs, run our error handler to output a tail of the build.
trap 'error_handler' ERR

## START BUILD

if [[ $(uname) == Darwin ]]; then
  # there apparently is a c++ header file being processed as c
  # this is supposed to help against the error "'type_traits' file not found"
  export CFLAGS="${CFLAGS} -stdlib=libc++"
  # compiler on macOS seems to ignore the CPPFLAGS variable
  # see https://clang.llvm.org/docs/CommandGuide/clang.html
  export CPATH="${CPATH}:${PREFIX}/include"
  # on macOS 10.13 with XCode 9.0 mediactrl.mm compile errors out at #import <AVFoundation/AVFoundation.h> with:
  # 'AVCaptureDeviceType' is unavailable: not available on macOS
  # turns out default wxWidgets build is with -mmacosx-version-min=10.5 whilst
  # AVFoundation.h looks like it needs at least 10.7
  # furthermore, we need at least 10.9 to be able to build with libc++ and avoid the dreaded
  # "strvararg.h:25:14: fatal error: 'type_traits' file not found" build error

  # This is done using a patch now
  # sed -i -e s/"--enable-mediactrl"/"--enable-mediactrl --with-macosx-version-min=10.9"/g buildtools/build_wxwidgets.py

  # Apparently waf build system creates the object files for all targets first
  # and then creates the shared libs and doesn't honour CXXFLAGS during the
  # linking stage, which leads to linking libstdc++ instead of libc++
  export LDFLAGS="$LDFLAGS -stdlib=libc++"

  # build documentation, etg and sip files before the real build starts
  # required for sip wrappings to be generated
  # we would only need this if it's a checkout, but we're using a snapshot which includes generated files
  # https://groups.google.com/d/msg/wxpython-dev/klFi8Ls7Ss8/RitVSbzt-GgJ
  # $PYTHON build.py dox etg --nodoc sip
  $PYTHON setup.py install --single-version-externally-managed --record record.txt  >> $BUILD_OUTPUT 2>&1
elif [[ $(uname) == Linux ]]; then
  export CPPFLAGS="${CPPFLAGS} -I${PREFIX}/include/GL -I${PREFIX}/include"

  # The configure script doesn't use --rpath-link :/
  if [[ ${ARCH} == 32 ]]; then
    export LD_LIBRARY_PATH="${BUILD_PREFIX}/${HOST}/sysroot/usr/lib"
  else
    export LD_LIBRARY_PATH="${BUILD_PREFIX}/${HOST}/sysroot/usr/lib64"
  fi

  # TEST 6/26/2021
  export build_alias="aarch64-unknown-linux-gnu"
  export host_alias="aarch64-unknown-linux-gnu"

  # TEST 6/25/2021
  #pushd build-aux
  #  rm config.guess
  #  curl -o config.guess ‘https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD’
  #  rm config.sub
  #  curl -o config.sub ‘https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD’
  #popd

  $PYTHON build.py build_wx install_wx --gtk2 --no_magic --prefix=$PREFIX --jobs=$CPU_COUNT >> $BUILD_OUTPUT 2>&1
  #$PYTHON build.py build_wx install_wx --gtk3 --no_magic --prefix=$PREFIX --jobs=$CPU_COUNT >> $BUILD_OUTPUT 2>&1

  $PYTHON build.py build_py install_py --gtk2 --no_magic --prefix=$PREFIX --jobs=$CPU_COUNT >> $BUILD_OUTPUT 2>&1
  #$PYTHON build.py build_py install_py --gtk3 --no_magic --prefix=$PREFIX --jobs=$CPU_COUNT >> $BUILD_OUTPUT 2>&1

fi

## END BUILD

# The build finished without returning an error so dump a tail of the output.
dump_output

# Nicely terminate the ping output loop.
kill $PING_LOOP_PID
