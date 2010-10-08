#!/bin/sh
# ========================================================================
# Copyright (c) 2006-2010 Intalio Inc
# ------------------------------------------------------------------------
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# and Apache License v2.0 which accompanies this distribution.
# The Eclipse Public License is available at 
# http://www.eclipse.org/legal/epl-v10.html
# The Apache License v2.0 is available at
# http://www.opensource.org/licenses/apache2.0.php
# You may elect to redistribute this code under either of these licenses. 
# ========================================================================
# Author hmalphettes, atoulme
# Sources published here: github.com/intalio/tycho-p2-scripts
##
# Invokes buildr with the buildfile that 
# Generates the deb packages out of the eclipse features.
# Collects the generated deb files into a single folder.
# Assumes that the features have been built by maven-tycho.

# Absolute path to this script.
SCRIPT=$(readlink -f $0)
# Absolute path this script is in.
SCRIPTPATH=`dirname $SCRIPT` 

BUILDR_FILE=$SCRIPTPATH/buildr-generate-deb-from-features.rb

if [ -z "$CURRENT_DIR" ]; then
 CURRENT_DIR=`pwd`
fi

if [ -z "$EMPTY_DEB_FOLDER" ]; then
  EMPTY_DEBS_FOLDER="" #false by default don't remove the previous debs. override only
fi

#clean up the deb file to files for paranoia reasons
find $CURRENT_DIR -type f -name "*.deb" -exec rm -f {} \;
buildr --buildfile $BUILDR_FILE package

if [ -z "$DEB_COLLECT_DIR" ]; then
 DEB_COLLECT_DIR=$CURRENT_DIR/generated_debs
fi
[ -n "$EMPTY_DEB_FOLDER" ] && rm -rf $DEB_COLLECT_DIR
mkdir -p $DEB_COLLECT_DIR

echo "moving in $DEB_COLLECT_DIR"
#exclude the directory where the debs are moved
#otherwise it will find the debs it just moved!
find $CURRENT_DIR -type f ! -path "$DEB_COLLECT_DIR/*" -name "*.deb" -exec mv -f {} $DEB_COLLECT_DIR \;

# move the gpl debs in their own folder if it exists
if [ -n "$DEB_GPL_COLLECT_DIR" ]; then
  [ -n "$EMPTY_DEB_FOLDER" ] && rm -rf $DEB_GPL_COLLECT_DIR
  mkdir -p $DEB_GPL_COLLECT_DIR
  find $DEB_COLLECT_DIR -type f -name "*gpl*.deb" -exec mv -f {} $DEB_GPL_COLLECT_DIR \;
fi
