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

if [ ! -f "computed-build-environment" ]; then
  currentdir = `pwd`
  echo "Could not find the file $currentdir/computed-build-environment was compute-environment.sh correctly executed?"
  exit 127
fi
. computed-build-environment

if  [ -n "$NO_SOURCE_CONTROLE_CHANGES" -o -n "$SKIP_TAG_AND_DEB_DEPLOYMENT_MSG" ]; then
  echo "$SKIP_TAG_AND_DEB_DEPLOYMENT_MSG NO_SOURCE_CONTROLE_CHANGES=$NO_SOURCE_CONTROLE_CHANGES"
  exit 0
fi

### Tag the source controle
set +e

tag=$completeVersion
[ -n "$SUB_DIRECTORY" ] && tag="$SUB_DIRECTORY-$completeVersion"

repo_report="pom.repositories_report.xml"
if [ -n "$GIT_BRANCH" ]; then
  if [ -n "$ROOT_POM" ]; then
    if [ -f "$repo_report" ]; then
      [ -f "$repo_report" ] && git add $repo_report
      git commit $ROOT_POM $repo_report -m "Release $completeVersion"
    else
      git commit $ROOT_POM -m "Release $completeVersion"
    fi
  else
     # when releasing the composite repository we need to commit the file
     [ -n "$restore_buildNumberLine" -o -n "$commit_Buildfile" ] && git commit Buildfile -m "Release $completeVersion"
     #in case it exists already delete the tag
     #we are not extremely strict about leaving a tag in there for ever and never touched it.
  fi
  #in case it exists already delete the tag
  #we are not extremely strict about leaving a tag in there for ever and never touched it.
  [ -n "$prop" ] && git push origin :refs/tags/$tag
  git tag $tag
  # don't push this pom in the master branch: we only care for it in the tag !
  # git push origin $GIT_BRANCH
  git push origin refs/tags/$tag
elif [ -d ".svn" ]; then
  if [ -n "$ROOT_POM" ]; then
    if [ -f "$repo_report" ]; then
      svn add $repo_report
      svn commit $ROOT_POM $repo_report -m "Release $completeVersion"
    else
      svn commit $ROOT_POM -m "Release $completeVersion"
    fi
    echo "Committed the pom.ml"
  else
    [ -n "$restore_buildNumberLine" -o -n "$commit_Buildfile" ] && svn commit Buildfile -m "Release $completeVersion"
    echo "Committed the $commit_Buildfile"
  fi
  #grab the trunk from which the checkout is done:
  svn_url=`svn info |grep URL`
  #for example: URL: http://io.intalio.com/svn/n3/intaliocrm/trunk
  svn_url=`echo "$svn_url" | awk 'match($0, "URL: (.*)/trunk", a) { print a[1] }'`
  #This should be for example: http://io.intalio.com/svn/n3/intaliocrm
  svn copy $svn_url/trunk $svn_url/tags/$tag
fi

set -e

#restore the commented out forceContextQualifier
if [ -n "$buildr_forced_build_number" ]; then
  #a forced build number, let's restore it the way it was
  buildNumber='${'$buildr_forced_build_number'}'
fi
[ -n $ROOT_POM ] && sed -i "s/<forceContextQualifier>.*<\/forceContextQualifier>/<!--forceContextQualifier>$buildNumber<\/forceContextQualifier-->/" $ROOT_POM
if [ -n "$GIT_BRANCH" ]; then
  if [ -n "$ROOT_POM" ]; then
    git commit $ROOT_POM -m "Restore $ROOT_POM for development"
  else
    git commit Buildfile -m "Restore Buildfile for development"
  fi
  #in case someone has been working and pushing things during the build:
  git pull origin $GIT_BRANCH
  git push origin $GIT_BRANCH
elif [ -d ".svn" ]; then
  #in case someone has been working and pushing things during the build:
  svn up
  if [ -n "$ROOT_POM" ]; then
    svn commit $ROOT_POM -m "Restore $ROOT_POM for development"
  else
    svn commit Buildfile -m "Restore Buildfile for development"
  fi
fi



