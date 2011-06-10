#!/bin/sh -e
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

# if this is a maven3-tycho build then go
# ahead and invoke the generic deb scritp
if [ -f "pom.xml" ]; then
  #clean up the deb file to files for paranoia reasons
  find $CURRENT_DIR -type f -name "*.deb" -exec rm -f {} \;
  buildr --buildfile $BUILDR_FILE package
  
  #now the bit of ruby that adds the csv files about the generated debs for each repositories.
  generate_deb_ius_path="$SCRIPTPATH/collect-deb-osgi-csv.rb"
  echo "Executing $generate_deb_ius_path"
  $generate_deb_ius_path

  echo "Exit code of $generate_deb_ius_path: $?"
fi
exit 0


