#!/usr/bin/env ruby

#####################################################################
# Hacky BS for Ruby SSL issue on Windows                            #
# Based on:                                                         # 
# https://gist.github.com/fnichol/867550#file-win_fetch_cacerts-rb  #
#####################################################################
require 'shell'
require 'net/http'

pwd = Shell.new.pwd
unless pwd[0] == '/'
  cacert_file = File.join(pwd, 'cacert.pem')
  ENV["SSL_CERT_FILE"] = cacert_file
  unless File.exists?(cacert_file)
    Net::HTTP.start("curl.haxx.se") do |http|
      resp = http.get("/ca/cacert.pem")
      if resp.code == "200"
        open(cacert_file, "wb") { |file| file.write(resp.body) }
      else
        p "There was a problem downloading cacert.pem"
        p "Please save this file into your #{pwd} directory:"
        p "\thttp://curl.haxx.se/ca/cacert.pem"
      end
    end
  end
end

##########################################
# The actual script                      #
##########################################
require_relative 'bots'

##########################################################
#  HACK: Force accepting expected fields in SimpleOAuth  #
##########################################################
SimpleOAuth::Header::ATTRIBUTE_KEYS << :consumer_secret
SimpleOAuth::Header::ATTRIBUTE_KEYS << :token_secret
####################### END HACK #########################


if ARGV[0] && ARGV[0] != 'start'
  Ebooks::Bot.get(ARGV[0]).start
else
  EM.run do
   Ebooks::Bot.all.each do |bot|
      bot.start
    end
  end
end