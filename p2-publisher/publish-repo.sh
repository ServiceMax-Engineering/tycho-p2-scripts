#!/bin/bash
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
# Simple script to invoke the publisher on a set of plugins and features already built.
#the folders are relative to the script.
ORI_CD=$(pwd)
cd `dirname $0`
script_dir=$(pwd)
cd $ORI_CD

source_folder=
if [ -d "$1" ]; then
  source_folder=$1
else
  source_folder=$script_dir
fi

echo "Invoking p2-publisher on $source_folder"

if [ ! -d "$source_folder/plugins" ]; then
  echo "WARN: no plugins folder inside $source_folder"
fi

if [ -z "$P2_DIRECTOR_HOME" ]; then
#no p2director home setup here. assume' "my" environment just to show what we expect
  P2_DIRECTOR_HOME="~/apps/EclipseRTP2DirectorExtended-3.7.0.v20110206"
fi
if [ ! -f "$P2_DIRECTOR_HOME/start.sh" ]; then
#complain loudly
  echo "Can't find the p2director with its feature and bundle publisher $P2_DIRECTOR_HOME"
  exit 2
fi 

#let's publish in place. note that the config argument does not seem to matter (?)
$P2_DIRECTOR_HOME/start.sh -application org.eclipse.equinox.p2.publisher.FeaturesAndBundlesPublisher \
   -metadataRepository file:/$script_dir/current \
   -artifactRepository file:/$script_dir/current \
   -source $script_dir/current \
   -configs gtk.linux.x86 \
   -compress \
   -publishArtifacts \
