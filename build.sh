#!/bin/bash

if [ $# -ne 1 ]; then
    echo "./build.sh version"
    exit
fi

mkdir _

deno compile -A -r --unstable --target x86_64-unknown-linux-gnu -o _/boa_linux_amd64 https://raw.githubusercontent.com/brook-community/boa/master/main.js
deno compile -A -r --unstable --target x86_64-apple-darwin -o _/boa_darwin_amd64 https://raw.githubusercontent.com/brook-community/boa/master/main.js

nami release github.com/brook-community/boa $1 _

rm -rf _
