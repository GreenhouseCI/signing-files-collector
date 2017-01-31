#!/bin/sh

INSTALL_DIR='/tmp/gh_ruby_gems'
echo $INSTALL_DIR

gem install --install-dir $INSTALL_DIR ruby-keychain plist

GEM_HOME=$INSTALL_DIR ruby signing_files_collector.rb

rm -rf $INSTALL_DIR