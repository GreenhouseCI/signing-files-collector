#!/bin/sh

INSTALL_DIR='/tmp/gh_ruby_gems'
PACKAGE_URL="http://127.0.0.1:3000/file"
LOG_URL="http://127.0.0.1:3000/file"
UPLOAD_KEY="12345678"

gem install --install-dir $INSTALL_DIR ruby-keychain plist

GEM_HOME=$INSTALL_DIR ruby signing_files_collector.rb $PACKAGE_URL $LOG_URL $UPLOAD_KEY

#rm -rf $INSTALL_DIR