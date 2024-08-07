#!/usr/bin/env bash
#  SPDX-License-Identifier: BSD-3-Clause
#  Copyright (C) 2022 Intel Corporation.
#  All rights reserved.
#

set -e

rootdir=$(readlink -f "$(dirname "$0")")
spdk_dir=$(readlink -f "$rootdir/spdk")
user_dir=false
force_checkout=true
force_build=true
revision=

function usage() {
	script_name="$(basename $0)"
	echo "Generate XML representation of the SPDK libraries for ABI tests."
	echo "Usage: $script_name -t <spdk_tag>"
	echo "    -t                        SPDK release tag"
	echo "    -x                        Location of resulting XML files. Default: ./\$spdk_tag.x"
	echo "    --spdk-path               Use SPDK from specified path. By default does not"
	echo "                              checkout or build SPDK in that path"
	echo "    --force-checkout[=<rev>]  Force checkout to the release tag or a specific revision"
	echo "    --force-build             Rebuilds SPDK according to predefined config"
	echo "    -h, --help                Print this help"
	echo "Example:"
	echo "$script_name -t v22.09 -x /path/for/generated/xmls"
	exit 0
}

function error() {
	printf "%s\n\n" "$1" >&2
	usage
	return 1
}

# Parse input arguments #
while getopts 'ht:x:-:' optchar; do
	case "$optchar" in
		-)
			case "$OPTARG" in
				help)
					usage
					exit 0
					;;
				spdk-path=*)
					spdk_dir="$(readlink -f ${OPTARG#*=})"
					user_dir=true
					force_checkout=false
					force_build=false
					;;
				force-checkout) force_checkout=true ;;
				force-checkout=*)
					force_checkout=true
					revision="${OPTARG#*=}"
					;;
				force-build) force_build=true ;;
				*) error ;;
			esac
			;;
		h)
			usage
			exit 0
			;;
		t) version="$OPTARG" ;;
		x) xml_dir="$OPTARG" ;;
		*) error ;;
	esac
done

case $version in
	v[0-9][0-9]\.[0-9][0-9]*) true ;;
	"") error "SPDK tag (-t) argument is required" ;;
	*) error "Incorrectly formatted SPDK tag (-t)" ;;
esac

function gitc() {
	git -C "$spdk_dir" "$@"
}

[[ -z "$revision" ]] && revision="$version"

if ! $user_dir; then
	# Clone a fresh spdk repository everytime the script is run
	[[ -d "$spdk_dir" ]] && rm -rf "$spdk_dir"
	git clone "https://github.com/spdk/spdk.git" $spdk_dir
fi

if $force_checkout; then
	gitc checkout "$revision"
	gitc submodule update --init

	gitc config --local user.name "spdk"
	gitc config --local user.email "hotpatch@spdk.io"

	# Make sure submodules point at proper commits after cherry-picks are applied
	gitc submodule update
fi

if $force_build; then
	# Hardcoded configure flags to keep backwards/forwards compatibility of the script.
	# When SPDK_TEST_* variable has no handling in get_config_params(), then script will still work.
	SPDK_TEST_BLOCKDEV=1
	SPDK_TEST_PMDK=1
	SPDK_TEST_ISAL=1
	SPDK_TEST_REDUCE=1
	SPDK_TEST_VBDEV_COMPRESS=1
	SPDK_TEST_CRYPTO=1
	SPDK_TEST_FTL=1
	SPDK_TEST_OCF=1
	SPDK_TEST_RAID5=1
	SPDK_TEST_RBD=1
	SPDK_TEST_NVME_PMR=1
	SPDK_TEST_NVME_SCC=1
	SPDK_TEST_NVME_BP=1
	SPDK_TEST_NVME_CUSE=1
	SPDK_TEST_BLOBFS=1
	SPDK_TEST_URING=1
	SPDK_TEST_VFIOUSER=1
	SPDK_TEST_XNVME=1

	# Set output_dir variable before sourcing autotest_common.sh, to prevent creation of that directory.
	rootdir="$spdk_dir" output_dir=none source $spdk_dir/test/common/autotest_common.sh
	config_params=$(get_config_params)
	config_params=$(echo $config_params | sed 's/--enable-coverage//g')
	config_params+=" --without-fio --disable-tests --disable-unit-tests --disable-apps --disable-examples"
	config_params+=" --with-shared --disable-werror"
	# Configure sets incorrect default path for the ocf while using --with-ocf flag and being out of the SPDK repo
	# The path must be provided to avoid directory missing error
	# GH issue #2735
	config_params+=" --with-ocf=$spdk_dir/ocf"

	$MAKE -C $spdk_dir clean || :

	$spdk_dir/configure $config_params

	$MAKE -C $spdk_dir $MAKEFLAGS
elif [[ ! -d "$spdk_dir/build" ]]; then
       echo "Please build SPDK in $spdk_dir first, or use --force-build."
       exit 1
fi

if [[ -z $xml_dir ]]; then
	branch=$(echo $version | grep -Eo 'v[0-9][0-9]\.[0-9][0-9]') branch="${branch}.x"
	xml_dir="$rootdir/$branch"
fi

if [[ -d "$xml_dir" ]]; then
	rm -rf "$xml_dir"
fi

# Copy headers from spdk/include to spdk-abi that are necessary for abidiff
# Skip config.h that is created during configure
mkdir -p "$xml_dir/include/"
cp -r "$spdk_dir/include/"{spdk,spdk_internal} "$xml_dir/include/"
rm -f "$xml_dir/include/spdk/config.h"

echo "$(gitc rev-parse HEAD)" > "$xml_dir/revision"

abidw_params="--type-id-style hash --drop-private-types --drop-undefined-syms"
abidw_params+=" --no-architecture --no-comp-dir-path --short-locs"
abidw_params+=" --no-corpus-path"
abidw_params+=" --headers-dir $xml_dir/include/"

for object in "$spdk_dir"/build/lib/libspdk_*.so; do
	libname=$(readlink $object)
	libso=$(basename $object)
	abidw "$object" $abidw_params --out-file "$xml_dir/$libname"
	ln -s "$libname" "$xml_dir/$libso"
done

if ! $user_dir; then
	# Cleaning
	rm -rf $spdk_dir
fi
