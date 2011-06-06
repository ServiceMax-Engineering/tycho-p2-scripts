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
