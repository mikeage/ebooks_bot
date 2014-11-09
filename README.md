twitter_ebooks
==============

Multi-user twitter ebooks bot

Based very heavily on:
* https://github.com/mispy/twitter_ebooks
* http://blog.boodoo.co/how-to-make-an-_ebooks/
* http://blog.boodoo.co/how-to-deploy-an-_ebooks-bot/

Basic instructions (this needs some major improvement)
* Register a new app at twitter; request R/W/DM priviledges
* Register one or more user names for your bot(s)
* Copy `.env.sample` to `.env`
* Set `EBOOKS_CONSUMER_KEY` & `EBOOKS_CONSUMER_SECRET` for your app
* Authorize each user using twurl: `twurl authorize --consumer-key <your_consumer_key> --consumer-secret <your_consumer_secret> -u <user_1> -p <user_1_password>`
* Copy 'token' and 'secret' from `~/.twurlrc` to `.env` (as `EBOOKS_OAUTH_TOKEN_*` and `EBOOKS_OAUTH_TOKEN_SECRET_*`)
* `gem install ebooks`
* `ebooks archive <user_to_learn_from> corpus/<botname>.json`
* `ebooks consume $( [ -f corpus/<botname>.csv ] && echo corpus/<botname>.csv) corpus/<botname>.json`
* Remove my models from `models/`
* `ruby run.rb`

Deploying to heroku:
* `heroku config:push` to copy .env to heroku

The default bot respond to the following commands
* talk / tweet / say something
* follow @foo
* favorite 1231434124 / favorite https://twitter.com/foo/status/241453412313
* reply to 3132131231 / respond to 1253252432

