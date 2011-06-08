#!/bin/bash

array=(one two three four five)

echo "Array size: ${#array[*]}"
array[4]=thefourth
array[$(expr 1 + ${#array[*]})]=six
echo "Array size: ${#array[*]}"

echo "Array items:"
for item in ${array[*]}
do
    printf "   %s\n" $item
done

echo "Array indexes:"
for index in ${!array[*]}
do
    printf "   %d\n" $index
done

echo "Array items and indexes:"
for index in ${!array[*]}
do
    printf "%4d: %s\n" $index ${array[$index]}
done
 
arr2=()
for nb in on tw th fo; do
  arr2[${#arr2[*]}]=$nb
done
echo "Arr2 items:"
for item in ${arr2[*]}; do
    printf "   %s\n" $item
done

echo "Arr2 items and indexes:"
for index in ${!arr2[*]}; do
    printf "%4d: %s\n" $index ${arr2[$index]}
done


function computeGroupIdForCompositeRepo() {
  #Computes the groupId. We are trying tp remain independent from buildr. Hence the following strategy:
  #Either a line starts with GROUP_ID= and extract the package like group id which is transformed
  #into a relative path.
  #Either reads the project's group. for example: project.group = "com.intalio.cloud" from the buildr's file
  #Assume a single project and assume that the first line where a 'project.group' is defined
  #is the interesting bit of information.
  Buildfile=$1
  if [ ! -f "$Buildfile" ];
    echo "Expecting the argument $Buildfile to be a file that exists."
    exit 127
  fi
  groupIdLine=`sed '/^GROUP_ID.*=/!d' $Buildfile | head -1`
  if [ -n "$groupIdLine" ]; then
    grpId=`echo "$groupIdLine" | sed -nr 's/^GROUP_ID.*=(.*)/\1/p' | sed 's/^[ \t]*//' | sed 's/"//g'`
    echo $grpId
  else
    groupIdLine=`sed '/^[ \t]*project\.group[ \t]*=/!d' $Buildfile | head -1`
    echo $groupIdLine
    if [ -n "$groupIdLine" ]; then
      grpId=`echo "$groupIdLine" | sed -nr 's/^[ \t]*project\.group[ \t]*=(.*)/\1/p;s/^[ \t]*//;s/[ \t]*$//' | sed 's/"//g'`
      echo $grpId
    fi
  fi
  if [ -z "$grpId" ]; then
    echo "Could not compute the grpId in $1"
  fi
}

