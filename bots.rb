require 'twitter_ebooks'

# Information about a particular Twitter user we know
class UserInfo
  attr_reader :username

  # @return [Integer] how many times we can pester this user unprompted
  attr_accessor :pesters_left

  # @param username [String]
  def initialize(username)
    @username = username
    @pesters_left = 1
  end
end

require 'dotenv'  
Dotenv.load(".env")

require 'open-uri'

NUMBER_BOTS = ENV['EBOOKS_NUMBER_BOTS']
CONSUMER_KEY = ENV['EBOOKS_CONSUMER_KEY']  
CONSUMER_SECRET = ENV['EBOOKS_CONSUMER_SECRET']  
ACCOUNTS=Hash.new
i = 1
while i <= NUMBER_BOTS.to_i do
	ACCOUNTS[i]={:admin => ENV['EBOOKS_ADMIN_USERNAME_'+i.to_s], :username => ENV['EBOOKS_USERNAME_'+i.to_s], :original => ENV['EBOOKS_ORIGINAL_'+i.to_s], :oauth_token => ENV['EBOOKS_OAUTH_TOKEN_'+i.to_s], :oauth_token_secret => ENV['EBOOKS_OAUTH_TOKEN_SECRET_'+i.to_s], :blacklist =>ENV['EBOOKS_BLACKLIST_'+i.to_s]}
	i+=1
end

class CloneBot < Ebooks::Bot
  attr_accessor :original, :model, :model_path
  attr_accessor :account, :admin

  def initialize(account)
	  @account = account
	  super account[:username]
  end

  def configure
    # Configuration for all CloneBots
    self.consumer_key = CONSUMER_KEY
    self.consumer_secret = CONSUMER_SECRET
    self.blacklist = account[:blacklist].split(",")

    self.access_token = account[:oauth_token]
    self.access_token_secret = account[:oauth_token_secret]

    self.original = account[:original]
    self.admin = account[:admin]

    @userinfo = {}
    
    load_model!
  end


  def top100; @top100 ||= model.keywords.take(100); end
  def top20;  @top20  ||= model.keywords.take(20); end

  def delay(&b)
    sleep (1..4).to_a.sample
    b.call
  end

  def on_startup
    scheduler.cron '0 0 * * *' do
      # Each day at midnight, post a single tweet
      tweet(model.make_statement)
    end
    scheduler.every '1m' do
      roll = rand
      chance = 80.0 / 100 / 120 # (80 % in 2 hours)
      if roll <= chance
        tweet(model.make_statement)
      end
    end
  end

  def on_message(dm)
    if @admin == dm.sender.screen_name
      command=dm.text.dup
      # ignore politephrases
      #bot.log "Got command \"#{command}\""
      politephrases =["please","thanks","thx","thank you","pls","kthxbai"]
      politephrases.each do |politephrase|
        command.gsub!(politephrase, "")
      end
      command.strip!()

      # Expand t.co URLs
      if command =~ /https?:\/\/t.co\/[^ \/]/
        url = command[/(https?:\/\/t.co\/[^ \/]+)/]

        open(url) do |h|
          final_uri = h.base_uri
          command.gsub!(url, final_uri.to_s)
        end
      end
      command.strip!()

      if command =~ /^talk|say something|tweet$/
        tweet(model.make_statement)
        return
      elsif command =~ /^favorite.*?[0-9]+$/
        tweet_id = command[/.*?([0-9]+)$/,1]
        tweet = twitter.status(tweet_id)
        begin
          favorite(tweet)
          reply(dm, "#{Time.now.getutc} As requested, favoriting @#{tweet.user.screen_name}: #{tweet.text[0,40]}...")
        rescue Twitter::Error::Forbidden
          reply(dm, "#{Time.now.getutc} Got Forbidden; couldn't favorite @#{tweet.user.screen_name}: #{tweet.text[0,40]}...")
        rescue 	
          reply(dm, "#{Time.now.getutc} Sorry, couldn't favorite @#{tweet.user.screen_name}: #{tweet.text[0,40]}...")
        end
        return
      elsif command =~ /^(reply to )|(respond to ).*?[0-9]+$/
        # TODO: port to 3.0.x!
        #tweet_id = command[/.*?([0-9]+)$/,1]
        #ev = bot.twitter.status(tweet_id)

        ## Copied from twitter_ebooks/bot.rb
        #meta = {}
        #mentions = ev.attrs[:entities][:user_mentions].map { |x| x[:screen_name] }

        #reply_mentions = mentions.reject { |m| m.downcase == bot.username.downcase }
        #reply_mentions = [ev[:user][:screen_name]] + reply_mentions

        #meta[:reply_prefix] = reply_mentions.uniq.map { |m| '@'+m }.join(' ') + ' '
        #meta[:limit] = 140 - meta[:reply_prefix].length

        #mless = ev[:text]
        #begin
        #ev.attrs[:entities][:user_mentions].reverse.each do |entity|
        #last = mless[entity[:indices][1]..-1]||''
        #mless = mless[0...entity[:indices][0]] + last.strip
        #end
        #rescue Exception
        #p ev.attrs[:entities][:user_mentions]
        #p ev[:text]
        #raise
        #end
        #meta[:mentionless] = mless
        #begin
        #reply(ev, meta, @prefix)
        #bot.reply dm, "#{Time.now.getutc} As requested, replied to @#{ev[:user][:screen_name]}: #{ev[:text][0,40]}..."
        #rescue 	
        #bot.reply dm, "#{Time.now.getutc} Sorry, couldn't reply to @#{ev[:user][:screen_name]}: #{ev[:text][0,40]}..."
        #end
        return
      elsif command =~ /^follow @?.+$/
        user = command[/follow @?(.+)$/,1]
        begin
          follow(user)
          reply(dm, "#{Time.now.getutc} As requested, followed @#{user}")
        rescue 	
          reply(dm, "#{Time.now.getutc} Sorry, couldn't follow @#{user}")
        end
        return
      end
    end
    delay do
      reply(dm, model.make_response(dm.text))
    end
  end

  def on_mention(tweet)
    # Become more inclined to pester a user when they talk to us
    userinfo(tweet.user.screen_name).pesters_left += 1

    delay do
      reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
    end
  end

  def on_timeline(tweet)
    return if tweet.retweeted_status?
    return unless can_pester?(tweet.user.screen_name)
    
    tokens = Ebooks::NLP.tokenize(tweet.text)

    interesting = tokens.find { |t| top100.include?(t.downcase) }
    very_interesting = tokens.find_all { |t| top20.include?(t.downcase) }.length > 2

    delay do
      if very_interesting
        favorite(tweet) if rand < 0.5
        retweet(tweet) if rand < 0.1
        reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit)) if rand < 0.05
      elsif interesting
        favorite(tweet) if rand < 0.05
        reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit)) if rand < 0.01
      end
    end
  end

  # Find information we've collected about a user
  # @param username [String]
  # @return [Ebooks::UserInfo]
  def userinfo(username)
    @userinfo[username] ||= UserInfo.new(username)
  end

  # Check if we're allowed to send unprompted tweets to a user
  # @param username [String]
  # @return [Boolean]
  def can_pester?(username)
    userinfo(username).pesters_left > 0
  end

  # Only follow our original user or people who are following our original user
  # @param user [Twitter::User]
  def can_follow?(username)
    @original.nil? || username == @original || twitter.friendship?(username, @original)
    true
  end

  def favorite(tweet)
    if can_follow?(tweet.user.screen_name)
      super(tweet)
    else
      log "Unfollowing @#{tweet.user.screen_name}"
      twitter.unfollow(tweet.user.screen_name)
    end
  end

  def on_follow(user)
    if can_follow?(user.screen_name)
      follow(user.screen_name)
    else
      log "Not following @#{user.screen_name}"
    end
  end
  
  private
  def load_model!
    return if @model

    @model_path ||= "model/#{original}.model"

    log "Loading model #{model_path}"
    @model = Ebooks::Model.load(model_path)
  end
end


# Make a CloneBot and attach it to an account
ACCOUNTS.each do |key, account|
	CloneBot.new(account)
end
