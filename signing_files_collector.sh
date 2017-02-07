#!/bin/sh

INSTALL_DIR='/tmp/gh_ruby_gems'
SIGNING_FILES_UPLOAD_URL="http://127.0.0.1:3000/"
LOG_URL="http://127.0.0.1:3000/file"
UPLOAD_KEY="12345678"

gem install --install-dir $INSTALL_DIR ruby-keychain plist

GEM_HOME=$INSTALL_DIR ruby signing_files_collector.rb $SIGNING_FILES_UPLOAD_URL $LOG_URL $UPLOAD_KEY

rm -rf $INSTALL_DIR