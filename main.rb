#!/usr/bin/env ruby
# frozen_string_literal: true

# Main entry point for the Seventeen Notify Discord Bot.
# It requires necessary gems, dependencies, configurations, and source files,
# sets up standard output syncing, and starts the bot instance.

require 'rubygems'
require 'bundler/setup'
require 'forwardable'
require 'json'
require 'net/http'
require 'tempfile'
require 'discordrb'
require './config'
require './src/subscription'
require './src/data'
require './src/command_manager'
require './src/monitor'
require './src/bot'

$stdout.sync = true
SeventeenNotifyDiscordBot::Bot.start
