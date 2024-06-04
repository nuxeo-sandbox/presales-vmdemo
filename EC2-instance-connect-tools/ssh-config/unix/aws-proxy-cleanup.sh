#!/usr/bin/env bash

FILES_TO_CLEAN=$1*

echo "I am here" >&2
echo $FILES_TO_CLEAN >&2

rm $FILES_TO_CLEAN
