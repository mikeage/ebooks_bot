#!/bin/bash

[ -f .env ] && source .env

i="1"
while [ $i -le $EBOOKS_NUMBER_BOTS ]
do
	URL="EBOOKS_MODEL_$i"
	LOCAL="EBOOKS_USERNAME_$i"
	wget -q ${!URL} -O model/${!LOCAL}.model

	i=$[$i+1]
done

ruby run.rb start
