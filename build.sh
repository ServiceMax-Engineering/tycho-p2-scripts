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

env_file=`pwd`
env_file="$env_file/computed-build-environment"
if [ ! -f "$env_file" ]; then
  SCRIPT=$(readlink -f $0)
  # Absolute path this script is in.
  SCRIPTPATH=`dirname $SCRIPT`
  $SCRIPTPATH/compute-environment.sh
fi
if [ ! -f "$env_file" ]; then
  currentdir = `pwd`
  echo "Could not find the file $currentdir/computed-build-environment was compute-environment.sh correctly executed?"
  exit 127
fi
chmod +x "$env_file"
. "$env_file"

if [ ! -d "$WORKSPACE_MODULE_FOLDER" ]; then
  echo "The constant WORKSPACE_MODULE_FOLDER doaes not exist. Was compute-environment.sh correctly executed?"
  exit 127
fi
echo "WORKSPACE_MODULE_FOLDER=$WORKSPACE_MODULE_FOLDER"
cd "$WORKSPACE_MODULE_FOLDER"
echo "At the moment: "`pwd`

#Run the deb generation
function generate_debs() {
  if [ -z "$DISABLE_DEB_GENERATION" ]; then
    path_to_deb_generation_script="$SCRIPTPATH/../osgi-features-to-debian-package/generate-and-collect-osgi-debs.sh"
    if [ ! -f "$path_to_deb_generation_script" ]; then
      #try a second location.
      path_to_deb_generation_script=$SCRIPTPATH/osgi-features-to-debian-package/generate-and-collect-osgi-debs.sh
    fi
    if [ ! -f "$path_to_deb_generation_script" ]; then
      echo "$path_to_deb_generation_script does not exist."
      echo "Unable to find the shell script in charge of generating the debian packages"
      exit 2;
    fi
    echo "Executing $path_to_deb_generation_script"
    $path_to_deb_generation_script
  else
    echo "No debian packages to build as the constant DISABLE_DEB_GENERATION is defined."
  fi
}

#Returns the grpId computed from a build file or something that follows the same format
function getGroupIdForCompositeRepo() {
  #Computes the groupId. We are trying tp remain independent from buildr. Hence the following strategy:
  #Either a line starts with GROUP_ID= and extract the package like group id which is transformed
  #into a relative path.
  #Either reads the project's group. for example: project.group = "com.intalio.cloud" from the buildr's file
  #Assume a single project and assume that the first line where a 'project.group' is defined
  #is the interesting bit of information.
  Buildfile=$1
  if [ ! -f "$Buildfile" ]; then
    echo "Expecting the argument $Buildfile to be a file that exists."
    exit 127
  fi
  groupIdLine=`sed '/^GROUP_ID.*=/!d' $Buildfile | head -1`
  if [ -n "$groupIdLine" ]; then
    grpId=`echo "$groupIdLine" | sed -nr 's/^GROUP_ID.*=(.*)/\1/p' | sed 's/^[ \t]*//' | sed 's/"//g'`
    echo $grpId
  else
    groupIdLine=`sed '/^[ \t]*project\.group[ \t]*=/!d' $Buildfile | head -1`
    #echo $groupIdLine
    if [ -n "$groupIdLine" ]; then
      grpId=`echo "$groupIdLine" | sed -nr 's/^[ \t]*project\.group[ \t]*=(.*)/\1/p;s/^[ \t]*//;s/[ \t]*$//' | sed 's/"//g'`
      echo $grpId
    fi
  fi
  if [ -z "$grpId" ]; then
    echo "Could not compute the grpId in $1"
    exit 127
  fi
}


if [ -n "$ROOT_POM" ]; then
  #update the numbers for the release
  sed -i "s/<!--forceContextQualifier>.*<\/forceContextQualifier-->/<forceContextQualifier>$buildNumber<\/forceContextQualifier>/" $ROOT_POM
  #### Build now
  $MAVEN3_HOME/bin/mvn -f $ROOT_POM clean verify -Dmaven.repo.local=$LOCAL_REPOSITORY
  generate_debs
elif [ -f Buildfile ]; then
  #update the numbers for the release
  sed -i "s/$buildNumberLine/VERSION_NUMBER=\"$completeVersion\"/" Buildfile

  #look for a composite repo to build first.
  composite_repo=`ls *.repos | head -1`
  if [ -n "$composite_repo" ]; then
    grpId=`getGroupIdForCompositeRepo Buildfile | tail -1`
    composite_basefolder=$HTTPD_ROOT_PATH
    #this would be the final output: #composite_output=$HTTPD_ROOT_PATH/`echo $grpId | tr '.' '/'`
    #let's use a classic target folder:
    composite_output=target/repository
    mkdir -p $composite_output
    generate_composite_repo_path=$SCRIPTPATH/composite-p2repo/generate_composite_repo.rb
    [ -n "$composite_otherurls" ] && composite_otherurls_param="--otherurls=$composite_otherurls"
    composite_name="$grpId"
    #cmd="$generate_composite_repo_path --name all --basefolder $HOME/p2repo/com/intalio/cloud/ --output $HOME/p2repo/com/intalio/cloud/all --otherurls=otherurls_for_composite_repo.txt"
    cmd="$generate_composite_repo_path --name $composite_name --basefolder $composite_basefolder --output $composite_output $composite_otherurls_param --version $completeVersion --symlinkname=$SYM_LINK_CURRENT_NAME"
    echo "Executing $cmd"
    $cmd
  fi

  buildr package

else
  echo "No pom.xml and no Buildfile: nothing to build?"
fi



