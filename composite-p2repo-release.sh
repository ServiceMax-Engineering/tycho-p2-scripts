#!/bin/sh -e
# Calls the generation of the composite repo
# Get the built version number of the composite repo
# Update the version number of the Buildfile for the deb package
# Calls the buildr package and deployment script

SCRIPT=$(readlink -f $0)
# Absolute path this script is in.
SCRIPTPATH=`dirname $SCRIPT`
#load the env
[ -z "$RELEASE_ENV" ] && RELEASE_ENV=$SCRIPTPATH/default_env
[ -f "$RELEASE_ENV" ] && . $RELEASE_ENV

if [ -d ".git" -a -z "$GIT_BRANCH" ]; then
  GIT_BRANCH=master
  export GIT_BRANCH
elif [ -z "$SYM_LINK_CURRENT_NAME" -a $GIT_BRANCH != "master" ]; then
  SYM_LINK_CURRENT_NAME="current_$GIT_BRANCH"
fi

if [ -z "$SYM_LINK_CURRENT_NAME" ]; then
  SYM_LINK_CURRENT_NAME="current"
fi


if [ -d ".git" ]; then
  git checkout $GIT_BRANCH
  git pull origin $GIT_BRANCH
elif [ -d ".svn" ]; then
  svn up
fi

if [ -n "$SUB_DIRECTORY" ]; then
  cd "$SUB_DIRECTORY"
fi

#sanity checks:
if [ -z "$composite_name" ]; then
  echo "Missing shell variable composite_name"
  exit 2;
fi
if [ -z "$composite_basefolder" ]; then
  echo "Missing shell variable composite_basefolder"
  exit 2;
fi
if [ -z "$composite_output" ]; then
  echo "Missing shell variable composite_output"
  exit 2;
fi
if [ -z "$composite_otherurls" ]; then
  echo "Missing shell variable composite_otherurls"
  exit 2;
fi

#compute the version number: read the one in the Buildfile if there is a Buildfile
#don't update the Buildfile and all: that will be done when the debs are released
versionParam=""
if [ -f "Buildfile" ]; then
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
  else
    reg2="VERSION_NUMBER=\\\"(.*)\\\""
    buildNumberLine=`awk '{if ($1 ~ /'$reg2'/){print $1}}' < Buildfile | head -1`
    echo "Release mode: forced version $buildNumberLine"
    completeVersion=`echo "$buildNumberLine" | awk 'match($0, "'$reg2'", a) { print a[1] }'`
    if [ -z "$" ]; then
      echo "Unable to find the $reg2 line in the Buildfile"
      exit 2
    fi
    props="forced_version"
  fi
  versionParam="--version $completeVersion"
fi

generate_composite_repo_path=$SCRIPTPATH/composite-p2repo/generate_composite_repo.rb
#cmd="$generate_composite_repo_path --name all --basefolder $HOME/p2repo/com/intalio/cloud/ --output $HOME/p2repo/com/intalio/cloud/all --otherurls=otherurls_for_composite_repo.txt"
cmd="$generate_composite_repo_path --name $composite_name --basefolder $composite_basefolder --output $composite_output --otherurls=$composite_otherurls $versionParam --symlinkname=$SYM_LINK_CURRENT_NAME"
echo "Executing $cmd"
$cmd

#make sure the Buildfile will be committed although it probably has no changes.
commit_Buildfile=true

if [ -n "$SUB_DIRECTORY" ]; then
  cd ..
fi

buildrdeb_release_path=$SCRIPTPATH/buildrdeb-release.sh
echo "Executing $buildrdeb_release_path"
$buildrdeb_release_path


