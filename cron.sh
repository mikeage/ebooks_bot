#!/bin/bash
set -e
MODEL_REPO=~/mikeage_ebooks_model
for sourcename in $(grep ORIGINAL .env | grep -v ADMIN |  cut -d"=" -f2)
do
	ebooks archive $sourcename
	ebooks consume corpus/${sourcename}.json
done
cp model/*model $MODEL_REPO/
pushd $MODEL_REPO
date=$(date)
#git commit -m "sync at $date" .
#git push origin master
popd
#heroku ps:restart 

