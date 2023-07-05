#!/usr/bin/env bash
#  SPDX-License-Identifier: BSD-3-Clause
#  Copyright (C) 2022 Intel Corporation.
#  All rights reserved.
#

set -e
spdk_url="https://review.spdk.io/spdk/spdk.git"

rootdir=$(readlink -f $(dirname $(readlink -f $0))/..)
tag_pattern="v[0-9][0-9]\.[0-9][0-9]"

trap 'rm -rf $rootdir/v*_test' EXIT SIGINT
for branch in $(ls $rootdir | grep -Eo "${tag_pattern}\.x"); do
	# Read hash from revision and get spdk_tag which it corresponds to
	hash=$(cat $rootdir/$branch/revision)
	# Get spdk_tag from the remote using commit hash from spdk-abi generated branch SO files
	spdk_tag=$(git ls-remote $spdk_url | grep $hash | grep -Po "${tag_pattern}.*(?=\^)")

	# Generate XML files and check if they differ from the user uploaded
	$rootdir/generate_xml_abi.sh -t $spdk_tag -x "$rootdir/${branch}_test"
	for lib in "$rootdir/${branch}_test"/libspdk_*.so; do
		lib_name=$(basename "$lib")
		if ! abidiff "$lib" "$rootdir/$branch/$lib_name"; then
			echo "$spdk_tag verification failed"
			exit 1
		fi
	done
	echo "Veryfing $spdk_tag completed - success"
done
