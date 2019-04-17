#!/bin/sh

set -P

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &>/dev/null && pwd )"

cd $DIR/../../../..

ZIP_PATH=lambda.zip

bundle install --deployment &>/dev/null
zip -r -X lambda.zip .bundle lambda.rb app vendor &>/dev/null
echo "{ \"path\": \"$(pwd)/${ZIP_PATH}\" }"
