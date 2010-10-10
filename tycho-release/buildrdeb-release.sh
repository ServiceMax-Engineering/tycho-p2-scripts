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
# Author hmalphettes
#
# Release script, takes care of auto-inc for buildr's Buildfile, commit tagging for svn and git
# Then invoke buildr package and deploys the generated debs in the specified repositories
#
# Clean
# Reads the main version number and delete '-SNAPSHOT' from it.
# Reads the buildNumber and increment it by 1. Pad it with zeros.
# Replace the context qualifier in the pom.xml by this buildNumber
# Build
# Commit and tags the sources (git or svn)
# Replace the forceContextQualifier's value by qualifier
# Commit
# git branch to checkout.
echo "Executing buildrdeb-release.sh in the folder "`pwd`
#make sure we are at the root of the folder where the chckout actually happened.
if [ ! -d ".git" -a ! -d ".svn" ]; then
  echo "FATAL: could not find .git or .svn in the Current Directory `pwd`"
  echo "The script must execute in the folder where the checkout of the sources occurred."
  exit 2;
fi

if [ -d ".git" -a -z "$GIT_BRANCH" ]; then
  GIT_BRANCH=master
  export GIT_BRANCH
fi

if [ -d ".git" ]; then
  git checkout $GIT_BRANCH
  git pull origin $GIT_BRANCH
fi

if [ -n "$SUB_DIRECTORY" ]; then
  cd $SUB_DIRECTORY
fi
### Compute the build number.
#tags the sources for a release build.
reg2="VERSION_NUMBER=\\\"(.*)-SNAPSHOT\\\""
buildNumberLine=`awk '{if ($1 ~ /'$reg2'/){print $1}}' < Buildfile | head -1`
if [ -n "$buildNumberLine" ]; then
  echo "Release mode: auto-increment $buildNumberLine"
  completeVersion=`echo "$buildNumberLine" | awk 'match($0, "'$reg2'", a) { print a[1] }'`

  # reconstruct the version and buildNumber.
  # make the assumption that the completeVersion matches a 4 seg numbers.
  var=$(echo $completeVersion | awk -F"." '{print $1,$2,$3,$4}')   
  set -- $var
  version=$1.$2.$3
  buildNumber=$4
  echo "$version   $buildNumber"
  echo "Increment the buildNumber $buildNumber"
  strlength=`expr length $buildNumber`
  #increment the context qualifier
  buildNumber=`expr $buildNumber + 1`
  #pad with zeros so the build number is as many characters long as before
  printf_format="%0"$strlength"d\n"
  buildNumber=`printf "$printf_format" "$buildNumber"`
  completeVersion="$version.$buildNumber"

  #update the numbers for the release
  sed -i "s/$buildNumberLine/VERSION_NUMBER=\"$completeVersion\"/" Buildfile
  #prepare the next dev build number line
  buildNumberLine="VERSION_NUMBER=\"$completeVersion-SNAPSHOT\""
  restore_buildNumberLine="true"
else
  reg2="VERSION_NUMBER=\\\"(.*)\\\""
  buildNumberLine=`awk '{if ($1 ~ /'$reg2'/){print $1}}' < Buildfile | head -1`
  echo "Release mode: forced version $buildNumberLine"
  completeVersion=`echo "$buildNumberLine" | awk 'match($0, "'$reg2'", a) { print a[1] }'`
  if [ -z "$" ]; then
    echo "Unable to find the $reg2 line in the Buildfile"
    exit 2
  fi
  
fi

export completeVersion
echo "Build Version $completeVersion"

#### Build now
buildr package

tag=$completeVersion
[ -n "$SUB_DIRECTORY" ] && tag="$SUB_DIRECTORY-$completeVersion"

### Tag the source controle
if [ -n "$GIT_BRANCH" ]; then
 # when releasing the composite repository we need to commit the file
  [ -n "$restore_buildNumberLine" -o -n "$commit_Buildfile" ] &&
  git commit Buildfile -m "Release $completeVersion"
  git tag $tag
  git push origin $GIT_BRANCH
  git push origin refs/tags/$tag
elif [ -d ".svn" ]; then
  [ -n "$restore_buildNumberLine" -o -n "$commit_Buildfile" ] && svn commit Buildfile -m "Release $completeVersion"
  echo "Committed the pom.ml"
  #grab the trunk from which the checkout is done:
  svn_url=`svn info |grep URL`
  #for example: URL: http://io.intalio.com/svn/n3/intaliocrm/trunk
  svn_url=`echo "$svn_url" | awk 'match($0, "URL: (.*)/trunk", a) { print a[1] }'`
  #This should be for example: http://io.intalio.com/svn/n3/intaliocrm
  svn copy $svn_url/trunk $svn_url/tags/$tag
fi

if [ -n "$restore_buildNumberLine" ]; then
  #restore the commented out forceContextQualifier
  sed -i "s/VERSION_NUMBER=\"$completeVersion\"/$buildNumberLine/" Buildfile
  if [ -n "$GIT_BRANCH" ]; then
    git commit Buildfile -m "Restore Buildfile for development"
    git push origin $GIT_BRANCH
  elif [ -d ".svn" ]; then
    svn commit pom.xml -m "Restore Buildfile for development"
  fi
fi

### Debian packages build
# Run it if indeed a location has been defined to deploy the deb packages.
if [ -n "$DEB_COLLECT_DIR" ]; then
  # Absolute path to this script.
  SCRIPT=$(readlink -f $0)
  # Absolute path this script is in.
  SCRIPTPATH=`dirname $SCRIPT` 
  path_to_deb_generation_script=$SCRIPTPATH/../osgi-features-to-debian-package/generate-and-collect-features-deb.sh
  if [ ! -f "$path_to_deb_generation_script" ]; then
    #try a second location.
    path_to_deb_generation_script=$SCRIPTPATH/osgi-features-to-debian-package/generate-and-collect-features-deb.sh
  fi
  if [ ! -f "$path_to_deb_generation_script" ]; then
    echo "$path_to_deb_generation_script does not exist."
    echo "Unable to find the shell script in charge of generating the debian packages"
    exit 2;
  fi
  echo "Executing $path_to_deb_generation_script"
  exec $path_to_deb_generation_script
else
  echo "No debian packages to build as the constant DEB_COLLECT_DIR is not defined."
fi

