#!/bin/sh

INSTALL_DIR='/tmp/gh_ruby_gems'
URL="http://127.0.0.1:8000/api/sigining-file-upload-url"
UPLOAD_KEY="12345678"

gem install --install-dir $INSTALL_DIR ruby-keychain plist

GEM_HOME=$INSTALL_DIR ruby signing_files_collector.rb $URL $UPLOAD_KEY

rm -rf $INSTALL_DIR