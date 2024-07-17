#!/usr/bin/env bash

if [ -z "$1" ]; then
    echo "Missing argument"
    echo "Usage: $0 versiontag"
    exit 1
fi

git status --short . && echo "ERROR: Repo is dirty" && exit 2

