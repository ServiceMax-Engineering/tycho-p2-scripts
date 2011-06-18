#!/bin/bash -e
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
# Author hmalphettes
#
# Release script, takes care of auto-inc for buildr's Buildfile, commit tagging for svn and git
# Then invoke buildr package and deploys the generated debs in the specified repositories
#
# Load the computed build environment
# Then invoke maven or build

#if [ ! -f "$env_file" ]; then
  SCRIPT=$(readlink -f $0)
  # Absolute path this script is in.
  SCRIPTPATH=`dirname $SCRIPT`
[ -f computed-build-environment ] && rm computed-build-environment

bash $SCRIPTPATH/sourcecontrol-checkout.sh
bash $SCRIPTPATH/compute-environment.sh
#fi
env_file=`pwd`
env_file="$env_file/computed-build-environment"
if [ ! -f "$env_file" ]; then
  currentdir = `pwd`
  echo "Could not find the file $currentdir/computed-build-environment was compute-environment.sh correctly executed?"
  exit 127
fi
chmod +x "$env_file"
. "$env_file"

cd $WORKSPACE_MODULE_FOLDER

bash $SCRIPTPATH/build.sh
bash $SCRIPTPATH/deploy.sh
bash $SCRIPTPATH/sourcecontrol-tag.sh


