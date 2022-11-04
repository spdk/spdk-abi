#!/usr/bin/env bash
set -e

rootdir=$(readlink -f $(dirname $0))/spdk
gcc_version=$(gcc -dumpversion) gcc_version=${gcc_version%%.*}
git_repo_spdk="https://github.com/spdk/spdk.git"

function usage() {
	script_name=./`basename "$0"`
	echo "Generate XML representation of the SPDK libraries for ABI tests."
	echo "Usage: $script_name <spdk_tag> [output_dir]"
	echo "spdk_tag      SPDK release tag"
	echo "output_dir    Location of resulting XML files. Default: ./\$spdk_tag.x"
	echo "Example:"
	echo "$script_name v22.09 /path/for/generated/xmls"
	exit 0
}

function gitc() {
	git -C "$rootdir" "$@"
}

version=$1
case $version in
	v[0-9][0-9]\.[0-9][0-9]*) true ;;
	*) usage ;;
esac
xml_dir=$2

# Clone a fresh spdk repository everytime the script is run
[[ -d "$rootdir" ]] && rm -rf "$rootdir"
git clone $git_repo_spdk $rootdir

gitc checkout $version
spdk_hash=$(gitc rev-parse HEAD)
gitc submodule update --init

gitc config --local user.name "spdk"
gitc config --local user.email "hotpatch@spdk.io"

# We have to cherry pick changes to properly build libs under the older releases
if ((gcc_version >= 11)); then
	if [[ "$version" =~ "22.05" ]]; then
		# https://review.spdk.io/gerrit/c/spdk/spdk/+/13404
		gitc cherry-pick 713506d5da4676b9f900ae59963f6eb50ecdba36
	elif [[ "$version" =~ "22.01" ]]; then
		# https://review.spdk.io/gerrit/c/spdk/spdk/+/13505
		gitc cherry-pick e255d79af097318e8f29c700a4639041f912a28c
		# https://review.spdk.io/gerrit/c/spdk/spdk/+/13506
		gitc cherry-pick a12cc7e4b9fb30f32dfb9afa1d5852128972b3e1
	fi
fi
# Make sure submodules point at proper commits after cherry-picks are applied
gitc submodule update

# Hardcoded configure flags to keep backwards/forwards compatibility of the script.
# When SPDK_TEST_* variable has no handling in get_config_params(), then script will still work.
SPDK_TEST_BLOCKDEV=1
SPDK_TEST_PMDK=1
SPDK_TEST_ISAL=1
SPDK_TEST_REDUCE=1
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

output_dir=none source $rootdir/test/common/autotest_common.sh
config_params=$(get_config_params)
config_params=$(echo $config_params | sed 's/--enable-coverage//g')
config_params+=" --without-fio --disable-tests --disable-unit-tests --disable-apps --disable-examples"
config_params+=" --with-shared --disable-werror"
# Configure sets incorrect default path for the ocf while using --with-ocf flag and being out of the SPDK repo
# The path must be provided to avoid directory missing error
# GH issue #2735
config_params+=" --with-ocf=$rootdir/ocf"

$rootdir/configure $config_params

$MAKE -C $rootdir $MAKEFLAGS

if [[ -z $xml_dir ]]; then
	branch=$(echo $version | grep -Eo 'v[0-9][0-9]\.[0-9][0-9]') branch="${branch}.x"
	xml_dir="$rootdir/../$branch"
fi

if [[ -d "$xml_dir" ]]; then
	rm -rf "$xml_dir"
fi

# Copy headers from spdk/include to spdk-abi that are necessary for abidiff
# Skip config.h that is created during configure
mkdir -p "$xml_dir/include/"
cp -r "$rootdir/include/"{spdk,spdk_internal} "$xml_dir/include/"
rm "$xml_dir/include/spdk/config.h"

echo $spdk_hash > "$xml_dir/revision"

abidw_params="--type-id-style hash --drop-private-types --drop-undefined-syms"
abidw_params+=" --no-architecture --no-comp-dir-path --no-show-locs"
abidw_params+=" --no-corpus-path"

for object in "$rootdir"/build/lib/libspdk_*.so; do
	libname=$(readlink $object)
	libso=$(basename $object)
	abidw "$object" $abidw_params --out-file "$xml_dir/$libname"
	ln -s "$libname" "$xml_dir/$libso"
done

# Cleaning
rm -rf $rootdir
