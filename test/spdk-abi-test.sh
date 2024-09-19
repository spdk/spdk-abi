#!/usr/bin/env bash
#  SPDX-License-Identifier: BSD-3-Clause
#  Copyright (C) 2022 Intel Corporation.
#  All rights reserved.
#

set -e

rootdir=$(readlink -f $(dirname $(readlink -f $0))/..)
repodir="$rootdir/test/spdk"
tag_pattern="v[0-9][0-9]\.[0-9][0-9]"

trap 'rm -rf "$rootdir"/v*_test "$repodir"' EXIT SIGINT
git clone --recursive "https://github.com/spdk/spdk" "$repodir"

for branch in $(ls $rootdir | grep -Eo "${tag_pattern}\.x"); do
	tag="${branch%*.x}"

	# Generate XML files and check if they differ from the user uploaded
	$rootdir/generate_xml_abi.sh -t "$tag" -x "$rootdir/${branch}_test" \
		--spdk-path="$repodir" --force-build --force-checkout="$(< "$branch/revision")"
	for lib in "$rootdir/${branch}_test"/libspdk_*.so; do
		lib_name=$(basename "$lib")
		if ! abidiff "$lib" "$rootdir/$branch/$lib_name"; then
			echo "$tag verification failed"
			exit 1
		fi
	done
	# We need need the --release option to run the check_so_deps test, which was only added in
	# 2dc96f6e2 ("test/check_so_deps: add option to specify release").  It was added in the
	# v24.09 release, so this check can be removed once we don't support anything older than
	# that.
	if git -C "$repodir" merge-base --is-ancestor 2dc96f6e2 HEAD; then
		(cd "$repodir"; "$repodir/test/make/check_so_deps.sh" --spdk-abi-path="$rootdir" \
			--release="$tag")
	fi
	echo "Veryfing $tag completed - success"
done
