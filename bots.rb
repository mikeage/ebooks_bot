#!/usr/bin/env ruby

require 'twitter_ebooks'
include Ebooks

require 'dotenv'  
Dotenv.load(".env")

NUMBER_BOTS = ENV['EBOOKS_NUMBER_BOTS']
CONSUMER_KEY = ENV['EBOOKS_CONSUMER_KEY']  
CONSUMER_SECRET = ENV['EBOOKS_CONSUMER_SECRET']  
ACCOUNTS=Hash.new
i = 1
while i <= NUMBER_BOTS.to_i do
	ACCOUNTS[i]={:admin => ENV['EBOOKS_ADMIN_USERNAME_'+i.to_s], :username => ENV['EBOOKS_USERNAME_'+i.to_s], :oauth_token => ENV['EBOOKS_OAUTH_TOKEN_'+i.to_s], :oauth_token_secret => ENV['EBOOKS_OAUTH_TOKEN_SECRET_'+i.to_s] }
	i+=1
end

ROBOT_ID = "_ebook" # Prefer not to talk to other robots

DELAY = 2..30 # Simulated human reply delay range, in seconds
BLACKLIST = ['tinysubversions', 'dril'] # users to avoid interaction with
SPECIAL_WORDS = ['singularity', 'world domination'] # Words we like
BANNED_WORDS = ['voldemort', 'evgeny morozov', 'heroku'] # Words we don't want to use

# Track who we've randomly interacted with globally
$have_talked = {}
$banned_words = BANNED_WORDS

# Overwrite the Model#valid_tweet? method to check for banned words
class Ebooks::Model
	def valid_tweet?(tikis, limit)
		tweet = NLP.reconstruct(tikis, @tokens)
		found_banned = $banned_words.any? do |word|
			re = Regexp.new("\\b#{word}\\b", "i")
			re.match tweet
		end
		tweet.length <= limit && !NLP.unmatched_enclosers?(tweet) && !found_banned
	end
end

class GenBot
	def initialize(bot, modelname, admin)
		@bot = bot
		@model = nil

		bot.consumer_key = CONSUMER_KEY
		bot.consumer_secret = CONSUMER_SECRET
		@admin = admin

		bot.on_startup do
			@model = Model.load("model/#{modelname}.model")
			@top100 = @model.keywords.top(100).map(&:to_s).map(&:downcase)
			@top50 = @model.keywords.top(20).map(&:to_s).map(&:downcase)
		end

		bot.on_message do |dm|
			# Check for known commands:
			# talk / "say something" / "tweet" (without "at XXX or to XX")
			# reply to XXX / respond to XXX (TODO)
			# reply to 12345 / respond to 12345 (TODO)
			# Note: my ruby sucks.

			if @admin == dm[:sender][:screen_name]
				command=dm[:text]
				# ignore politephrases
				#bot.log "Got command \"#{command}\""
				politephrases =["please","thanks","thx","thank you","pls","kthxbai"]
				politephrases.each do |politephrase|
					command.gsub!(politephrase, "")
				end
				command.strip!()

				# When
				if command =~ /right now$/ 
					delay = 0
					command.gsub!("right now", "")
				else
					delay = DELAY 
				end
				command.strip!()
				#bot.log "parsed command \"#{command}\". Delay is #{delay}"

				if command =~ /^talk|say something|tweet$/
					bot.delay delay do
						bot.tweet @model.make_statement
					end
					next
				elsif command =~ /^favorite.*?[0-9]+$/
					tweet_id = command[/.*?([0-9]+)$/,1]
					bot.delay delay do
						tweet = bot.twitter.status(tweet_id)
						begin
							bot.twitter.favorite(tweet_id)
							bot.reply dm, "As requested, favoriting @#{tweet[:user][:screen_name]}: #{tweet[:text][0,40]}..."
						rescue Twitter::Error::Forbidden
							bot.reply dm, "Got Forbidden; couldn't favorite @#{tweet[:user][:screen_name]}: #{tweet[:text][0,40]}..."
						rescue 	
							bot.reply dm, "Sorry, couldn't favorite @#{tweet[:user][:screen_name]}: #{tweet[:text][0,40]}..."
						end
					end
					next
				end
			end

			bot.delay DELAY do
				bot.reply dm, @model.make_response(dm[:text])
			end
		end

		bot.on_follow do |user|
			bot.delay DELAY do
				bot.follow user[:screen_name]
			end
		end

		bot.on_mention do |tweet, meta|
			# Avoid infinite reply chains
			# s/0.05/0.25 to be chattier
			next if tweet[:user][:screen_name].include?(ROBOT_ID) && rand > 0.25

			author = tweet[:user][:screen_name]
			next if $have_talked.fetch(author, 0) >= 5
			$have_talked[author] = $have_talked.fetch(author, 0) + 1

			tokens = NLP.tokenize(tweet[:text])
			very_interesting = tokens.find_all { |t| @top50.include?(t.downcase) }.length > 2
			special = tokens.find { |t| SPECIAL_WORDS.include?(t) }

			if very_interesting || special
				favorite(tweet)
			end

			reply(tweet, meta)
		end

		bot.on_timeline do |tweet, meta|
			next if tweet[:retweeted_status] || tweet[:text].start_with?('RT')
			author = tweet[:user][:screen_name]
			next if BLACKLIST.include?(author)

			tokens = NLP.tokenize(tweet[:text])

			# We calculate unprompted interaction probability by how well a
			# tweet matches our keywords
			interesting = tokens.find { |t| @top100.include?(t.downcase) }
			very_interesting = tokens.find_all { |t| @top50.include?(t.downcase) }.length > 2
			special = tokens.find { |t| SPECIAL_WORDS.include?(t) }

			if special
				favorite(tweet)
				favd = true # Mark this tweet as favorited

				bot.delay DELAY do
					bot.follow author
				end
			end

			# Any given user will receive at most one random interaction per 12h
			# (barring special cases)
			next if $have_talked[author]
			$have_talked[author] = $have_talked.fetch(author, 0) + 1

			if very_interesting || special
				favorite(tweet) if (rand < 0.5 && !favd) # Don't fav the tweet if we did earlier
				retweet(tweet) if rand < 0.1
				reply(tweet, meta) if rand < 0.1
			elsif interesting
				favorite(tweet) if rand < 0.1
				reply(tweet, meta) if rand < 0.05
			end
		end

		# Reset list of mention recipients every 12 hrs:
		bot.scheduler.every '12h' do
			$have_talked = {}
		end

		# 80% chance to tweet every 2 hours
		bot.scheduler.every '1m' do
			roll = rand
			chance = 80.0 / 100 / 120 # (80 % in 2 hours)
			if roll <= chance
				bot.tweet @model.make_statement
			end
		end
	end

	def reply(tweet, meta)
		resp = @model.make_response(meta[:mentionless], meta[:limit])
		@bot.delay DELAY do
			@bot.reply tweet, meta[:reply_prefix] + resp
		end
	end

	def favorite(tweet)
		@bot.log "Favoriting @#{tweet[:user][:screen_name]}: #{tweet[:text]}"
		@bot.delay DELAY do
			@bot.twitter.favorite(tweet[:id])
		end
	end

	def retweet(tweet)
		@bot.log "Retweeting @#{tweet[:user][:screen_name]}: #{tweet[:text]}"
		@bot.delay DELAY do
			@bot.twitter.retweet(tweet[:id])
		end
	end
end

def make_bot(bot, modelname, admin)
	GenBot.new(bot, modelname, admin)
end

ACCOUNTS.each do |key, account|
	Ebooks::Bot.new(account[:username]) do |bot|
		bot.oauth_token = account[:oauth_token]
		bot.oauth_token_secret = account[:oauth_token_secret]

		make_bot(bot, account[:username], account[:admin])
		#account+=1

	end
end
