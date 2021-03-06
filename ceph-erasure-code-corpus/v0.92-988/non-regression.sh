#!/bin/bash
#
# Copyright (C) 2014, 2015 Red Hat <contact@redhat.com>
# Copyright (C) 2015 FUJITSU LIMITED
#
# Author: Loic Dachary <loic@dachary.org>
# Authro: Miyamae, Takeshi <miyamae.takeshi@jp.fujitsu.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU Library Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Library Public License for more details.
#
: ${ACTION:=--check}
: ${STRIPE_WIDTHS:=4096 4651 8192 10000 65000 65536}
: ${VERBOSE:=} # VERBOSE=--debug-osd=20
: ${JERASURE_VARIANTS:=generic sse3 sse4}
: ${MYDIR:=--base $(dirname $0)}

TMP=$(mktemp --directory)
trap "rm -fr $TMP" EXIT

function non_regression() {
    local action=$1
    shift

    if test $action != NOOP ; then
        ceph_erasure_code_non_regression $action "$@" || return 1
    fi
    ceph_erasure_code_non_regression --show-path "$@" >> $TMP/used
}

function verify_directories() {
    local base=$(dirname "$(head -1 $TMP/used)")
    ls "$base" | grep 'plugin=' | sort > $TMP/exist_sorted
    sed -e 's|.*/||' $TMP/used | sort > $TMP/used_sorted
    if ! cmp $TMP/used_sorted $TMP/exist_sorted ; then
        echo "The following directories contain a payload that should have been verified"
        echo "but they have not been. It probably means that a change in the script"
        echo "made it skip these directories. If the modification is intended, the directories"
        echo "should be removed."
        comm -13 $TMP/used_sorted $TMP/exist_sorted
        return 1
    fi
}

function shec_variants() {
    local variant
    variant=$(default_variant shec) || return 1
    echo -n 'generic '
    case $variant in
        shec_sse4) echo sse3 sse4 ;;
        shec_sse3) echo sse3 ;;
        shec_neon) echo neon ;;
    esac
}

function shec_action() {
    local action=$1
    shift

    non_regression $action "$@" || return 1
    if test "$action" = --check ; then
        path=$(ceph_erasure_code_non_regression --show-path "$@")
        #
        # Verify all variants of the shec plugin encode/decode in the same
        # way, although they use a different code path.
        #
        local variants
        variants=$(shec_variants) || return 1
        for variant in $variants ; do
            ceph_erasure_code_non_regression $action "$@" --path "$path" --parameter shec-variant=$variant || return 1
        done
    fi
}

function test_shec() {
    while read k m c ; do
        for stripe_width in $STRIPE_WIDTHS ; do
            shec_action $ACTION --stripe-width $stripe_width --plugin shec --parameter technique=multiple --parameter k=$k --parameter m=$m --parameter c=$c $VERBOSE $MYDIR || return 1
        done
    done <<EOF
1 1 1
2 1 1
3 2 1
3 2 2
3 3 2
4 1 1
4 2 2
4 3 2
5 2 1
6 3 2
6 4 2
6 4 3
7 2 1
8 3 2
8 4 2
8 4 3
9 4 2
9 5 3
12 7 4
EOF
}

function test_lrc() {
    while read k m l ; do
        for stripe_width in $STRIPE_WIDTHS ; do
            non_regression $ACTION --stripe-width $stripe_width --plugin lrc --parameter k=$k --parameter m=$m --parameter l=$l $VERBOSE $MYDIR || return 1
        done
    done <<EOF
2 2 2
4 2 3
8 4 3
EOF
}

function test_isa() {
    local action=$ACTION

    if ! ceph_erasure_code --plugin_exists isa ; then
        action=NOOP
    fi

    while read k m ; do
        for technique in reed_sol_van cauchy ; do
            for stripe_width in $STRIPE_WIDTHS ; do
                non_regression $action --stripe-width $stripe_width --plugin isa --parameter technique=$technique --parameter k=$k --parameter m=$m $VERBOSE $MYDIR || return 1
            done
        done
    done <<EOF
2 1
3 1
3 2
4 2
4 3
7 3
7 4
8 3
8 4
9 3
9 4
10 4
EOF
}

function default_variant() {
    local plugin=$1
    ceph_erasure_code --debug-osd 20 --plugin_exists $plugin > $TMP/variant.txt 2>&1 || return 1
    eval variant=$(sed -e 's/.*load: *//' < $TMP/variant.txt)
    echo $variant
}

function jerasure_variants() {
    local variant
    variant=$(default_variant jerasure) || return 1
    echo -n 'generic '
    case $variant in
        jerasure_sse4) echo sse3 sse4 ;;
        jerasure_sse3) echo sse3 ;;
        jerasure_neon) echo neon ;;
    esac
}

function jerasure_action() {
    local action=$1
    shift

    non_regression $action "$@" || return 1
    if test "$action" = --check ; then
        path=$(ceph_erasure_code_non_regression --show-path "$@")
        #
        # Verify all variants of the jerasure plugin encode/decode in the same
        # way, although they use a different code path.
        #
        local variants
        variants=$(jerasure_variants) || return 1
        for variant in $variants ; do
            ceph_erasure_code_non_regression $action "$@" --path "$path" --parameter jerasure-variant=$variant || return 1
        done
    fi
}

function test_jerasure() {
    while read k m ; do
        for stripe_width in $STRIPE_WIDTHS ; do
            for technique in cauchy_good cauchy_orig ; do
                for alignment in '' '--parameter jerasure-per-chunk-alignment=true' ; do
                    jerasure_action $ACTION --stripe-width $stripe_width --parameter packetsize=32 --plugin jerasure --parameter technique=$technique --parameter k=$k --parameter m=$m $alignment $VERBOSE $MYDIR || return 1
                done
            done
        done
    done <<EOF
2 1
3 1
3 2
4 2
4 3
7 3
7 4
7 5
8 3
8 4
9 3
9 4
9 5
9 6
EOF

    while read k m ; do
        for stripe_width in $STRIPE_WIDTHS ; do
            for alignment in '' '--parameter jerasure-per-chunk-alignment=true' ; do
                jerasure_action $ACTION --stripe-width $stripe_width --plugin jerasure --parameter technique=reed_sol_van --parameter k=$k --parameter m=$m $alignment $VERBOSE $MYDIR || return 1
            done
        done
    done <<EOF
2 1
3 1
3 2
4 2
4 3
7 3
7 4
7 5
8 3
8 4
9 3
9 4
9 5
9 6
EOF

    for k in $(seq 2 6) ; do
        for stripe_width in $STRIPE_WIDTHS ; do
            for technique in reed_sol_r6_op liberation blaum_roth liber8tion ; do
                for alignment in '' '--parameter jerasure-per-chunk-alignment=true' ; do
                    jerasure_action $ACTION --stripe-width $stripe_width --parameter packetsize=32 --plugin jerasure --parameter technique=$technique --parameter k=$k --parameter m=2 $alignment $VERBOSE $MYDIR || return 1
                done
            done
        done
    done
}

function run() {
    local all_funcs=$(set | sed -n -e 's/^\(test_[0-9a-z_]*\) .*/\1/p')
    local funcs=${@:-$all_funcs}
    PS4="$0":'$LINENO: ${FUNCNAME[0]} '
    set -x
    for func in $funcs ; do
        $func || return 1
    done
    if test "$all_funcs" = "$funcs" ; then
        verify_directories || return 1
    fi
}

run "$@" || exit 1
