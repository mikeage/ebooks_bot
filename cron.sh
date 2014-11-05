#!/bin/bash
set -e
MODEL_REPO=~/mikeage_ebooks_model
for botname in $(grep USERNAME .env | grep -v ADMIN |  cut -d"=" -f2)
do
	sourcename=$(echo $botname | sed -r -e "s/_ebooks?$//" -e "s/_bot$//")
	ebooks archive $sourcename corpus/$botname.json
	ebooks consume $( [ -f corpus/$botname.csv ] && echo corpus/$botname.csv) corpus/$botname.json
done
cp model/*model $MODEL_REPO/
pushd $MODEL_REPO
date=$(date)
git commit -m "sync at $date" .
git push origin master
popd
heroku ps:restart 

