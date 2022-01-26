#!/bin/bash

if [ $# -ne 1 ]; then
    echo "./build.sh version"
    exit
fi

mkdir _

deno compile -A -r --unstable --target x86_64-unknown-linux-gnu -o _/jinbe_linux_amd64 https://raw.githubusercontent.com/txthinking/jinbe/master/main.js
deno compile -A -r --unstable --target x86_64-apple-darwin -o _/jinbe_darwin_amd64 https://raw.githubusercontent.com/txthinking/jinbe/master/main.js
deno compile -A -r --unstable --target aarch64-apple-darwin -o _/jinbe_darwin_arm64 https://raw.githubusercontent.com/txthinking/jinbe/master/main.js

nami release github.com/txthinking/jinbe $1 _

rm -rf _
