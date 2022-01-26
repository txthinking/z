#!/bin/bash

if [ $# -ne 1 ]; then
    echo "./build.sh version"
    exit
fi

mkdir _

deno compile -A -r --unstable --target x86_64-unknown-linux-gnu -o _/jinbe_linux_amd64 https://raw.githubusercontent.com/txthinking/jinbe/master/main.js
deno compile -A -r --unstable --target x86_64-apple-darwin -o _/jinbe_darwin_amd64 https://raw.githubusercontent.com/txthinking/jinbe/master/main.js

#install upx first
upx _/*

nami release github.com/txthinking/jinbe $1 _

rm -rf _
