#!/bin/bash
#
# $Id: bld.sh,v 1.2 2012/09/22 16:04:19 jlinoff Exp jlinoff $
#
# Author: Joe Linoff
#
# This script downloads, builds and installs the gcc-4.7.2 compiler
# and boost 1.51. It takes handles the dependent packages like
# gmp-5.0.5, mpfr-3.1.1, ppl-1.0 and cloog-0.17.0.
#
# To install gcc-4.7.2 in ~/tmp/gcc-4.7.2/rtf/bin you would run this
# script as follows:
#
#    % # Install in ~/tmp/gcc-4.7.2/rtf/bin
#    % bld.sh ~/tmp/gcc-4.7.2 2>&1 | tee bld.log
#
# If you do not specify a directory, then it will install in the
# current directory which means that following command will also
# install in ~/tmp/gcc-4.7.2/rtf/bin:
#
#    % # Install in ~/tmp/gcc-4.7.2/rtf/bin
#    % mkdir -p ~/tmp/gcc-4.7.2
#    % cd ~/tmp/gcc-4.7.2
#    % bld.sh 2>&1 | tee bld.log
#
# This script creates 4 subdirectories:
#
#    Directory  Description
#    =========  ==================================================
#    archives   This is where the package archives are downloaded.
#    src        This is where the package source is located.
#    bld        This is where the packages are built from source.
#    rtf        This is where the packages are installed.
#
# When the build is complete you can safely remove the archives, bld
# and src directory trees to save disk space.
#
# Copyright (C) 2012 Joe Linoff
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# ================================================================
# Trim a string, remove internal spaces, convert to lower case.
# ================================================================
function get-platform-trim {
    local s=$(echo "$1" | tr -d '[ \t]' | tr 'A-Z' 'a-z')
    echo $s
}

# ================================================================
# Get the platform root name.
# ================================================================
function get-platform-root
{
    if which uname >/dev/null 2>&1 ; then
        # Greg Moeller reported that the original code didn't
        # work because the -o option is not available on solaris.
        # I modified the script to correctly identify that
        # case and recover by using the -s option.
        if uname -o >/dev/null 2>&1 ; then
            # Linux distro
            uname -o | tr 'A-Z' 'a-z'
        elif uname -s >/dev/null 2>&1 ; then
            # Solaris variant
            uname -s | tr 'A-Z' 'a-z'
        else
            echo "unkown"
        fi
    else
        echo "unkown"
    fi
}

# ================================================================
# Get the platform identifier.
#
# The format of the output is:
#   <plat>-<dist>-<ver>-<arch>
#   ^      ^      ^     ^
#   |      |      |     +----- architecture: x86_64, i86pc, etc.
#   |      |      +----------- version: 5.5, 4.7
#   |      +------------------ distribution: centos, rhel, nexentaos
#   +------------------------- platform: linux, sunos
#
# ================================================================
function get-platform
{
    plat=$(get-platform-root)
    case "$plat" in
        "gnu/linux")
            d=$(get-platform-trim "$(lsb_release -i)" | awk -F: '{print $2;}')
            r=$(get-platform-trim "$(lsb_release -r)" | awk -F: '{print $2;}')
            m=$(get-platform-trim "$(uname -m)")
            if [[ "$d" == "redhatenterprise"* ]] ; then
                # Need a little help for Red Hat because
                # they don't make the minor version obvious.
                d="rhel_${d:16}"  # keep the tail (e.g., es or client)
                x=$(get-platform-trim "$(lsb_release -c)" | \
                    awk -F: '{print $2;}' | \
                    sed -e 's/[^0-9]//g')
                r="$r.$x"
            fi
            echo "linux-$d-$r-$m"
            ;;
        "cygwin")
            x=$(get-platform-trim "$(uname)")
            echo "linux-$x"
            ;;
        "sunos")
            d=$(get-platform-trim "$(uname -v)")
            r=$(get-platform-trim "$(uname -r)")
            m=$(get-platform-trim "$(uname -m)")
            echo "sunos-$d-$r-$m"
            ;;
        "unknown")
            echo "unk-unk-unk-unk"
            ;;
        *)
            echo "$plat-unk-unk-unk"
            ;;
    esac
}

# Execute command with decorations and status testing.
# Usage  : docmd $ar <cmd>
# Example: docmd $ar ls -l
function docmd {
    local ar=$1
    shift
    local cmd=($*)
    echo 
    echo " # ================================================================"
    if [[ "$ar" != "" ]] ; then
	echo " # Archive: $ar"
    fi
    echo " # PWD: "$(pwd)
    echo " # CMD: "${cmd[@]}
    echo " # ================================================================"
    ${cmd[@]}
    local st=$?
    echo "STATUS = $st"
    if (( $st != 0 )) ; then
	exit $st;
    fi
}

# Report an error and exit.
# Usage  : doerr <line1> [<line2> .. <line(n)>]
# Example: doerr "line 1 msg"
# Example: doerr "line 1 msg" "line 2 msg"
function doerr {
    local prefix="ERROR: "
    for ln in "$@" ; do
	echo "${prefix}${ln}"
	prefix="       "
    done
    exit 1
}

# Extract archive information.
# Usage  : ard=( $(extract-ar-info $ar) )
# Example: ard=( $(extract-ar-info $ar) )
#          fn=${ard[1]}
#          ext=${ard[2]}
#          d=${ard[3]}
function extract-ar-info {
    local ar=$1
    local fn=$(basename $ar)
    local ext=$(echo $fn | awk -F. '{print $NF}')
    local d=${fn%.*tar.$ext}
    echo $ar
    echo $fn
    echo $ext
    echo $d
}

# Print a banner for a new section.
# Usage  : banner STEP $ar
# Example: banner "DOWNLOAD" $ar
# Example: banner "BUILD" $ar
function banner {
    local step=$1
    local ard=( $(extract-ar-info $2) )
    local ar=${ard[0]}
    local fn=${ard[1]}
    local ext=${ard[2]}
    local d=${ard[3]}
    echo
    echo '# ================================================================'
    echo "# Step   : $step"
    echo "# Archive: $ar"
    echo "# File   : $fn"
    echo "# Ext    : $ext"
    echo "# Dir    : $d"
    echo '# ================================================================'
}

# Make a group directories
# Usage  : mkdirs <dir1> [<dir2> .. <dir(n)>]
# Example: mkdirs foo bar spam spam/foo/bar
function mkdirs {
    local ds=($*)
    #echo "mkdirs"
    for d in ${ds[@]} ; do
	#echo "  testing $d"
	if [ ! -d $d ] ; then
	    #echo "    creating $d"
	    mkdir -p $d
	fi
    done
}

# ================================================================
# Check the current platform to see if it is in the tested list,
# if it isn't, then issue a warning.
# ================================================================
function check-platform
{
    local plat=$(get-platform)
    local tested_plats=(
	'linux-centos-5.5-x86_64'
	'linux-centos-5.8-x86_64'
	'linux-centos-6.3-x86_64')
    local plat_found=0

    echo "PLATFORM: $plat"
    for tested_plat in ${tested_plats[@]} ; do
	if [[ "$plat" == "$tested_plat" ]] ; then
	    plat_found=1
	    break
	fi
    done
    if (( $plat_found == 0 )) ; then
	echo "WARNING: This platform ($plat) has not been tested."
    fi
}

# ================================================================
# DATA
# ================================================================
# List of archives
# The order is important.
ARS=(
    http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz
    ftp://ftp.gmplib.org/pub/gmp-5.0.5/gmp-5.0.5.tar.bz2
    http://www.mpfr.org/mpfr-current/mpfr-3.1.1.tar.bz2
    http://www.multiprecision.org/mpc/download/mpc-1.0.tar.gz
    http://bugseng.com/products/ppl/download/ftp/releases/1.0/ppl-1.0.tar.bz2
    http://www.bastoul.net/cloog/pages/download/cloog-0.17.0.tar.gz
    http://ftp.gnu.org/gnu/gcc/gcc-4.6.3/gcc-4.6.3.tar.bz2
    http://ftp.gnu.org/gnu/binutils/binutils-2.22.tar.bz2

    #
    # Why glibc is disabled (for now).
    #
    # glibc does not work on CentOS because the versions of the shared
    # libraries we are building are not compatiable with installed
    # shared libraries.
    #
    # This is the run-time error: ELF file OS ABI invalid that I see
    # when I try to run binaries compiled with the local glibc-2.15.
    #
    # Note that the oldest supported ABI for glibc-2.15 is 2.2. The
    # CentOS 5.5 ABI is 0.
    # http://ftp.gnu.org/gnu/glibc/glibc-2.15.tar.bz2
)

# ================================================================
# MAIN
# ================================================================
umask 0

check-platform

# Read the command line argument, if it exists.
ROOTDIR=$(readlink -f .)
if (( $# == 1 )) ; then
    ROOTDIR=$(readlink -f $1)
elif (( $# > 1 )) ; then
    doerr "too many command line arguments ($#), only zero or one is allowed" "foo"
fi

# Setup the directories.
ARDIR="$ROOTDIR/archives"
RTFDIR="$ROOTDIR/rtf"
SRCDIR="$ROOTDIR/src"
BLDDIR="$ROOTDIR/bld"
TSTDIR="$SRCDIR/LOCAL-TEST"

export PATH="${RTFDIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${RTFDIR}/lib:${LD_LIBRARY_PATH}"

echo
echo "# ================================================================"
echo '# Version    : $Id: bld.sh,v 1.2 2012/09/22 16:04:19 jlinoff Exp jlinoff $'
echo "# RootDir    : $ROOTDIR"
echo "# ArchiveDir : $ARDIR"
echo "# RtfDir     : $RTFDIR"
echo "# SrcDir     : $SRCDIR"
echo "# BldDir     : $BLDDIR"
echo "# TstDir     : $TSTDIR"
echo "# Gcc        : "$(which gcc)
echo "# GccVersion : "$(gcc --version | head -1)
echo "# Hostname   : "$(hostname)
echo "# O/S        : "$(uname -s -r -v -m)
echo "# Date       : "$(date)
echo "# ================================================================"

mkdirs $ARDIR $RTFDIR $SRCDIR $BLDDIR

# ================================================================
# Download
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'DOWNLOAD' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    if [  -f "${ARDIR}/$fn" ] ; then
	echo "skipping $fn"
    else
	# get
	docmd $ar wget $ar -O "${ARDIR}/$fn"
    fi
done

# ================================================================
# Extract
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'EXTRACT' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    sd="$SRCDIR/$d"
    if [ -d $sd ] ; then
	echo "skipping $fn"
    else
	# unpack
	pushd $SRCDIR
	case "$ext" in
	    "bz2")
		docmd $ar tar jxf ${ARDIR}/$fn
		;;
	    "gz")
		docmd $ar tar zxf ${ARDIR}/$fn
		;;
	    "tar")
		docmd $ar tar xf ${ARDIR}/$fn
		;;
	    *)
		doerr "unrecognized extension: $ext" "Can't continue."
		;;
	esac
	popd
	if [ ! -d $sd ] ;  then
	    # Some archives (like gcc-g++) overlay. We create a dummy
	    # directory to avoid extracting them every time.
	    mkdir -p $sd
	fi
    fi
done

# ================================================================
# Build
# ================================================================
for ar in ${ARS[@]} ; do
    banner 'BUILD' $ar
    ard=( $(extract-ar-info $ar) )
    fn=${ard[1]}
    ext=${ard[2]}
    d=${ard[3]}
    sd="$SRCDIR/$d"
    bd="$BLDDIR/$d"
    if [ -d $bd ] ; then
	echo "skipping $sd"
    else
        # Build
	if [ $(expr match "$fn" 'gcc-g++') -ne 0 ] ; then
            # Don't build/configure the gcc-g++ package explicitly because
	    # it is part of the regular gcc package.
	    echo "skipping $sd"
	    # Dummy
	    continue
	fi

        # Set the CONF_ARGS
	in_bld=1 # build in the bld area
	run_conf=1
	run_bootstrap=0
	case "$d" in
	    binutils-*)
		# Binutils will not compile with strict error
		# checking on so I disabled -Werror by setting
		# --disable-werror.
		CONF_ARGS=(
		    --disable-cloog-version-check
		    --disable-werror
		    --enable-cloog-backend=isl
		    --enable-lto
		    --enable-libssp
		    --enable-gold
		    --prefix=${RTFDIR}
		    --with-cloog=${RTFDIR}
		    --with-gmp=${RTFDIR}
		    --with-mlgmp=${RTFDIR}
		    --with-mpc=${RTFDIR}
		    --with-mpfr=${RTFDIR}
		    --with-ppl=${RTFDIR}
		    CC=${RTFDIR}/bin/gcc
		    CXX=${RTFDIR}/bin/g++
		)
		# We need to make a special fix here to the configure
		# script because it chokes on ppl 1.x.
		src="$sd/configure"
		if [ -f $src ] ; then
		    if [ ! -f $src.orig ] ; then
			mv $src $src.orig
			sed -e 's/#if PPL_VERSION_MAJOR != 0 || PPL_VERSION_MINOR < 11/#if PPL_VERSION_MAJOR != 1/' \
			    $src.orig > $src
			chmod a+x $src
		    fi
		fi
		;;

	    boost_*)
		# The boost configuration scheme requires
		# that the build occur in the source directory.
		run_conf=0
		run_bootstrap=1
		in_bld=0
		CONF_ARGS=(
		    --prefix=${RTFDIR}
		    --with-python=python2.7
		)
		;;

	    cloog-*)
		GMPDIR=$(ls -1d ${BLDDIR}/gmp-*)
		CONF_ARGS=(
		    --prefix=${RTFDIR}
		    --with-gmp-builddir=${GMPDIR}
		    --with-gmp=build
		    ## --with-isl=system
		)
		;;

	    gcc-*)
		# We are using a newer version of CLooG (0.17.0).
		# I have also made stack protection available
		# (similar to DEP in windows).
		CONF_ARGS=(
                    --enable-libstdcxx-time=yes
                    --disable-multilib
		    --disable-cloog-version-check
		    --disable-ppl-version-check
		    --enable-cloog-backend=isl
		    --enable-gold
		    --enable-languages='c,c++'
		    --enable-lto
		    --enable-libssp
		    --prefix=${RTFDIR}
		    --with-cloog=${RTFDIR}
		    --with-gmp=${RTFDIR}
		    --with-mlgmp=${RTFDIR}
		    --with-mpc=${RTFDIR}
		    --with-mpfr=${RTFDIR}
		    --with-ppl=${RTFDIR}
		)
		# We need to make a special fix here to the configure
		# script because it chokes on ppl 1.x.
		src="$sd/configure"
		if [ -f $src ] ; then
		    if [ ! -f $src.orig ] ; then
			mv $src $src.orig
			sed -e 's/#if PPL_VERSION_MAJOR != 0 || PPL_VERSION_MINOR < 11/#if PPL_VERSION_MAJOR != 1/' \
			    $src.orig > $src
			chmod a+x $src
		    fi
		fi

                # We need to make a special fix here for
                # supporting CLooG 0.17.0. Between 0.16.0
                # and 0.17.0 they changed LANGUAGE_C to
                # CLOOG_LANGUAGE_C which was the correct
                # thing to do but it means that we have
                # to change one of the source files in
                # the distribution.
                src="$sd/gcc/graphite-clast-to-gimple.c"
                if [ -f $src ] ; then
                    if [ ! -f $src.orig ] ; then
                        mv $src $src.orig
                        sed -e 's/ LANGUAGE_C/ CLOOG_LANGUAGE_C/g' \
                            $src.orig > $src
                    fi
                fi
                ;;


	    glibc-*)
		CONF_ARGS=(
		    --enable-static-nss=no
		    --prefix=${RTFDIR}
		    --with-binutils=${RTFDIR}
		    --with-elf
		    CC=${RTFDIR}/bin/gcc
		    CXX=${RTFDIR}/bin/g++
		)
		;;

	    gmp-*)
		CONF_ARGS=(
		    --enable-cxx
		    --prefix=${RTFDIR}
		)
		;;

	    libiconv-*)
		CONF_ARGS=(
		    --prefix=${RTFDIR}
		)
		;;

	    mpc-*)
		CONF_ARGS=(
		    --prefix=${RTFDIR}
		    --with-gmp=${RTFDIR}
		    --with-mpfr=${RTFDIR}
		)
		;;

	    mpfr-*)
		CONF_ARGS=(
		    --prefix=${RTFDIR}
		    --with-gmp=${RTFDIR}
		)
		;;

	    ppl-*)
		CONF_ARGS=(
		    --prefix=${RTFDIR}
		    --with-gmp=${RTFDIR}
		)
		;;

	    *)
		doerr "unrecognized package: $d"
		;;
	esac

	if (( $in_bld )) ; then
	    mkdir -p $bd
	    pushd $bd
	else
	    echo "NOTE: This package must be built in the source directory."
	    pushd $sd
	fi
	if (( $run_conf )) ; then
	    docmd $ar $sd/configure --help
	    docmd $ar $sd/configure ${CONF_ARGS[@]}
	    docmd $ar make
	    docmd $ar make install
	fi
	if (( $run_bootstrap )) ; then
	    docmd $ar which g++
	    docmd $ar $sd/bootstrap.sh --help
	    docmd $ar $sd/bootstrap.sh ${CONF_ARGS[@]}
	    docmd $ar ./b2
	    docmd $ar ./b2 install
	fi

	# Redo the tests if anything changed.
	if [ -d $TSTDIR ] ; then
	    rm -rf $TSTDIR
	fi
	popd
    fi
done

# ================================================================
# Test
# ================================================================
if [ -d $TSTDIR ] ; then
    echo "skipping tests"
else
    docmd "MKDIR" mkdir -p $TSTDIR
    pushd $TSTDIR
    docmd "LOCAL TEST  1" which g++
    docmd "LOCAL TEST  2" which gcc
    docmd "LOCAL TEST  3" which c++
    docmd "LOCAL TEST  4" g++ --version

    # Simple aliveness test.
    cat >test1.cc <<EOF
#include <iostream>
using namespace std;
int main()
{
  cout << "IO works" << endl;
  return 0;
}
EOF
    docmd "LOCAL TEST  5" g++ -O3 -Wall -o test1.bin test1.cc
    docmd "LOCAL TEST  6" ./test1.bin

    docmd "LOCAL TEST  7" g++ -g -Wall -o test1.dbg test1.cc
    docmd "LOCAL TEST  8" ./test1.dbg

    # Simple aliveness test for boost.
    cat >test2.cc <<EOF
#include <iostream>
#include <boost/algorithm/string.hpp>
using namespace std;
using namespace boost;
int main()
{
  string s1(" hello world! ");
  cout << "value      : '" << s1 << "'" <<endl;

  to_upper(s1);
  cout << "to_upper() : '" << s1 << "'" <<endl;

  trim(s1);
  cout << "trim()     : '" << s1 << "'" <<endl;

  return 0;
}
EOF
    docmd "LOCAL TEST  9" g++ -O3 -Wall -o test2.bin test2.cc
    docmd "LOCAL TEST 10" ./test2.bin

    docmd "LOCAL TEST 11" g++ -g -Wall -o test2.dbg test2.cc
    docmd "LOCAL TEST 12" ./test2.dbg

    docmd "LOCAL TEST" ls -l 
    popd
fi

