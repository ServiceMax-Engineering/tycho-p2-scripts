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
# Computes the environment and writes it down into a temporary shell script that will be
# committed into the source repository as part of the build..
# Every subsequent script will load it.
#
#load the environment constants
# Absolute path to this script.

SCRIPT=$(readlink -f $0)
# Absolute path this script is in.
SCRIPTPATH=`dirname $SCRIPT`
[ -z "$RELEASE_ENV" ] && RELEASE_ENV=$SCRIPTPATH/default_env
[ -f "$RELEASE_ENV" ] && . $RELEASE_ENV

WORKSPACE_FOLDER=`pwd`

echo "Executing compute-environment.sh in the folder "`pwd`
#make sure we are at the root of the folder where the chckout actually happened.
if [ ! -d ".git" -a ! -d ".svn" -a -z "$NO_SOURCE_CONTROL_UPDATES" ]; then
  echo "FATAL: could not find .git or .svn in the Current Directory `pwd`"
  echo "The script must execute in the folder where the checkout of the sources occurred."
  exit 2;
fi

if [ -z "$MAVEN3_HOME" ]; then
  MAVEN3_HOME=~/tools/apache-maven-3.0-beta-1
fi

if [ -d ".git" ]; then
  git branch
  if [ -z "$GIT_BRANCH" ]; then
    #trust the hudson job to have checked out the proper branch:
    GIT_BRANCH=`git branch | sed '/^\* /!d' | head -1 | sed 's/^\* //'`
    if [ -z "$GIT_BRANCH" ]; then
      echo "ERROR: Not able to read the current branch: no branch checked out and no GIT_BRANCH constant defined here "`pwd`
      echo "git branch"
      echo `git branch`
      exit 127
    fi
  fi
  export GIT_BRANCH
  export BRANCH="$GIT_BRANCH"
elif [ -d ".svn" ]; then
    #By default assume the svn classic layout: parent folder is the name of the branch.
    [ -z "$SVN_BRANCH" ] && SVN_BRANCH=$(basename `pwd`)
    export SVN_BRANCH
    export BRANCH="$SVN_BRANCH"
else
    export BRANCH="trunk"
fi

if [ -z "$SYM_LINK_CURRENT_NAME"]; then
  SYM_LINK_CURRENT_NAME="current"
fi

#Base folder on the file system where the p2-repositories are deployed.
if [ -z "$BASE_FILE_PATH_P2_REPO" ]; then
  #Assume we are on the release machine logged in as the release user.
  BASE_FILE_PATH_P2_REPO=$HOME/p2repo
fi

if [ -z "$SYM_LINK_CURRENT_NAME" ]; then
  SYM_LINK_CURRENT_NAME="current"
fi

if [ -z "$NO_SOURCE_CONTROL_UPDATES" ]; then
  if [ -d ".git" ]; then
    git checkout $GIT_BRANCH
    git pull origin $GIT_BRANCH
  elif [ -d ".svn" ]; then
    svn up
  fi
fi

# Create the local Maven repository.
if [ -z "$LOCAL_REPOSITORY" ]; then
  LOCAL_REPOSITORY=".repository"
fi

if [ -n "$SUB_DIRECTORY" ]; then
  cd $SUB_DIRECTORY
fi
WORKSPACE_MODULE_FOLDER=`pwd`


if [ -z "$ROOT_POM" ]; then
  ROOT_POM="pom.xml"
fi

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


#we write this one in the build file
timestamp_and_id=`date +%Y-%m-%d-%H%M%S`
timestamp_and_id_forqualifier=`date +%Y%m%d%H%M`
if [ -f "$ROOT_POM" ]; then
echo "ROOT_POM $ROOT_POM"

  ### Compute the build number.
  #tags the sources for a release build.
  reg="<version>(.*)-SNAPSHOT<\/version>"
  line=`awk '{if ($1 ~ /'$reg'/){print $1}}' < $ROOT_POM | head -1`
  version=`echo "$line" | awk 'match($0, "<version>(.*)-SNAPSHOT</version>", a) { print a[1] }'`
  
  if [ -n "$forceContextQualifier" ]; then
    buildNumber=$forceContextQualifier
    completeVersion="$version.$buildNumber"
  elif [ -n "$useTimestamptForContextQualifier" ]; then
    buildNumber=$timestamp_and_id_forqualifier
    completeVersion="$version.$buildNumber"
  else
    reg2="<!--forceContextQualifier>(.*)<\/forceContextQualifier-->"
    buildNumberLine=`awk '{if ($1 ~ /'$reg2'/){print $1}}' < $ROOT_POM | head -1`
    echo "buildNumberLine $buildNumberLine"
    if [ -z "$buildNumberLine" ]; then
      echo "Could not find the build-number to use in $ROOT_POM; The line $reg2 must be defined"
      exit 2;
    fi
    currentBuildNumber=`echo "$buildNumberLine" | awk 'match($0, "'$reg2'", a) { print a[1] }'`

    reg_prop=".{(.*)}"
    forcedBuildVersion=`echo "$currentBuildNumber" | awk 'match($0, "'$reg_prop'", a) { print a[1] }'`
    if [ -n "$forcedBuildVersion" ]; then
      echo "Force the buildNumber to match the value of the property $forcedBuildVersion"
      reg_named_prop="<$forcedBuildVersion>(.*)<\/$forcedBuildVersion>"
      line_prop=`awk '{if ($1 ~ /'$reg_named_prop'/){print $1}}' < $ROOT_POM | head -1`
      completeVersion=`echo "$line_prop" | awk 'match($0, "'$reg_named_prop'", a) { print a[1] }'`
      # reconstruct the version and buildNumber.
      # make the assumption that the completeVersion matches a 4 seg numbers.
      #if it does not then make the assumption that this buildNumber is just the forced context qualifier and use 
      #the pom.xml's version for the rest of the version.
      var=$(echo $completeVersion | awk -F"." '{print $1,$2,$3,$4}')   
      set -- $var
      if [ -n "$1" -a -n "$2" -a -n "$3" -a -n "$4" ]; then
        version=$1.$2.$3
        buildNumber=$4
      else
        buildNumber=$completeVersion
        completeVersion="$version.$buildNumber"
      fi
      echo "$version   $buildNumber"
    else
      echo "Increment the buildNumber $currentBuildNumber"
      strlength=`expr length $currentBuildNumber`
      #increment the context qualifier
      buildNumber=`expr $currentBuildNumber + 1`
      #pad with zeros so the build number is as many characters long as before
      printf_format="%0"$strlength"d\n"
      buildNumber=`printf "$printf_format" "$buildNumber"`
      completeVersion="$version.$buildNumber"
    fi
  fi
else
  if [ -f "Buildfile_n" ]; then
    #found the new Buildfile
    echo "Found the Builfile updated by the previous part of the build"
    rm Buildfile_n
  fi
  if [ ! -f "Buildfile" ]; then
    echo "Build failed: Could not find the pom.xml file and the Buildfile"
    exit 14
  fi
  ROOT_POM=""

  ### Compute the build number.
  #tags the sources for a release build.
  buildNumberLine=`sed '/^VERSION_NUMBER=\".*-SNAPSHOT\"/!d' Buildfile`
  if [ -n "$buildNumberLine" ]; then
    echo "Release mode: auto-increment $buildNumberLine"
    completeVersion=`echo $buildNumberLine | sed 's/ /\//g' | sed 's/^VERSION_NUMBER=\"//g' | sed 's/-SNAPSHOT\"//g'`

    # reconstruct the version and buildNumber.
    # make the assumption that the completeVersion matches a 4 seg numbers.
    var=$(echo $completeVersion | awk -F"." '{print $1,$2,$3,$4}')
    set -- $var
    if [ -n "$1" -a -n "$2" -a -n "$3" -a -n "$4" ]; then
    version=$1.$2.$3
    buildNumber=$4
    else
      echo "Invalid VERSION_NUMBER $completeVersion. Expecting 4 tokens; for example: 1.2.3.004-SNAPSHOT."
      exit 14
    fi
    strlength=`expr length $buildNumber`
    #format the context qualifier
    buildNumber=`expr $buildNumber`
    #pad with zeros so the build number is as many characters long as before
    printf_format="%0"$strlength"d\n"
    buildNumber=`printf "$printf_format" "$buildNumber"`
    completeVersion="$version.$buildNumber"

  else
    reg2="VERSION_NUMBER=\\\"(.*)\\\""
    buildNumberLine=`awk '{if ($1 ~ /'$reg2'/){print $1}}' < Buildfile | head -1`
    echo "Release mode: forced version $buildNumberLine"
    completeVersion=`echo "$buildNumberLine" | awk 'match($0, "'$reg2'", a) { print a[1] }'`
    if [ -z "$" ]; then
      echo "Unable to find the $reg2 line in the Buildfile"
      exit 2
    fi
    if [ -n "$1" -a -n "$2" -a -n "$3" -a -n "$4" ]; then
      version=$1.$2.$3
      buildNumber=$4
    fi
    buildr_forced_build_number=$buildNumberLine
  fi
  #format the context qualifier
  nextBuildNumber=`expr $buildNumber + 1`
  #pad with zeros so the build number is as many characters long as before
  printf_format="%0"$strlength"d\n"
  nextBuildNumber=`printf "$printf_format" "$nextBuildNumber"`
  nextCompleteVersion="$version.$nextBuildNumber"

  #prepare the next dev build number line
  buildNumberLine="VERSION_NUMBER=\"$completeVersion-SNAPSHOT\""
  nextBuildNumberLine="VERSION_NUMBER=\"$nextCompleteVersion-SNAPSHOT\""
  restore_buildNumberLine="true"

  export grpIdForCompositeRepo=`getGroupIdForCompositeRepo Buildfile | tail -1`
  

fi

export completeVersion
export version
export buildNumber
echo "Build Version $completeVersion"

esc_buildNumberLine=`echo "$buildNumberLine" | sed -e 's/[\"]/\\\"/g'`
esc_nextBuildNumberLine=`echo "$nextBuildNumberLine" | sed -e 's/[\"]/\\\"/g'`
esc_buildr_forced_build_number=`echo "$buildr_forced_build_number" | sed -e 's/[\"]/\\\"/g'`

quote='"'
squote="'"
echo "# Computed build environment on $timestamp_and_id
export SCRIPTPATH=$quote$SCRIPTPATH$quote
export RELEASE_ENV=$quote$RELEASE_ENV$quote

export MAVEN3_HOME=$quote$MAVEN3_HOME$quote
#The maven local repository
export LOCAL_REPOSITORY=$quote$LOCAL_REPOSITORY$quote
#The branch name:
export BRANCH=$quote$BRANCH$quote
#The git branch
export GIT_BRANCH=$quote$GIT_BRANCH$quote
#The directory inside which the project is located. (or empty)
export SUB_DIRECTORY=$quote$SUB_DIRECTORY$quote
#Path to the folder that is served as the root path of the web server for the p2 and apt repos.
export HTTPD_ROOT_PATH=$quote$HTTPD_ROOT_PATH$quote

#path to the folder inside which the build was started
export WORKSPACE_FOLDER=$quote$WORKSPACE_FOLDER$quote
#path to the folder inside which the module to build is checked out.
export WORKSPACE_MODULE_FOLDER=$quote$WORKSPACE_MODULE_FOLDER$quote

#When empty this build is a buildr build
export ROOT_POM=$quote$ROOT_POM$quote

#when not empty it is used as the base folder where the artifacts are placed on the filesystem
export BASE_FILE_PATH_P2_REPO=$quote$BASE_FILE_PATH_P2_REPO$quote
#when not empty it turns off the tagging and deb deployment.
export SKIP_TAG_AND_DEB_DEPLOYMENT_MSG=$quote$SKIP_TAG_AND_DEB_DEPLOYMENT_MSG$quote
#Skip all source control updates, tagging and commits when not empty
export NO_SOURCE_CONTROL_UPDATES=$quote$NO_SOURCE_CONTROL_UPDATES$quote
#Skip all source controle tags and commits when not empty
export NO_SOURCE_CONTROL_TAG_COMMIT=$quote$NO_SOURCE_CONTROL_TAG_COMMIT$quote

#Name of the symbolic link created on the file system to point at the latest built repository
export SYM_LINK_CURRENT_NAME=$quote$SYM_LINK_CURRENT_NAME$quote
#When not empty force the name of the folder where the repository is deployed
export P2_DEPLOYMENT_FOLDER_NAME=$quote$P2_DEPLOYMENT_FOLDER_NAME$quote

#When not empty disables the debian package generation
export DISABLE_DEB_GENERATION=$quote$DISABLE_DEB_GENERATION$quote

export timestamp_and_id=$quote$timestamp_and_id$quote
export timestamp_and_id_forqualifier=$quote$timestamp_and_id_forqualifier$quote

#when not empty the timestamp is used as the qualifier
export useTimestamptForContextQualifier=$quote$useTimestamptForContextQualifier$quote
export version=$quote$version$quote
export buildNumber=$quote$buildNumber$quote
export completeVersion=$quote$completeVersion$quote
export nextBuildNumber=$quote$nextBuildNumber$quote
export nextCompleteVersion=$quote$nextCompleteVersion$quote

export forceContextQualifier=$quote$forceContextQualifier$quote
export buildr_forced_build_number=$quote$esc_buildr_forced_build_number$quote
export nextBuildNumberLine=$quote$esc_nextBuildNumberLine$quote
export restore_buildNumberLine=$quote$restore_buildNumberLine$quote
export commit_Buildfile=$quote$commit_Buildfile$quote
export buildNumberLine=$quote$esc_buildNumberLine$quote

export grpIdForCompositeRepo=$quote$grpIdForCompositeRepo$quote

#When not null will be used to override the location of the deployed repo.
export groupId=$quote$groupId$quote

#JENKINS/HUDSON
export BUILD_NUMBER=$quote$BUILD_NUMBER$quote
export BUILD_URL=$quote$BUILD_URL$quote
export JOB_URL=$quote$JOB_URL$quote
export NODE_NAME=$quote$NODE_NAME$quote
export NODE_LABELS=$quote$NODE_LABELS$quote

" > computed-build-environment


