# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The Bot class serves as the main orchestrator.
  # It ties together data persistence, command handling, and background monitoring,
  # and manages the lifecycle of the Discordrb client.
  class Bot
    # Convenience method to instantiate and run the bot.
    #
    # @return [void]
    def self.start
      new.start
    end

    # Initializes the bot's internal components including the data store,
    # command manager, and stream monitor. Configures the Discord client
    # and ensures graceful shutdown on exit.
    #
    # @return [void]
    def initialize
      @data = Data.new
      @bot = Discordrb::Bot.new token: Config::DISCORD_TOKEN, intents: :unprivileged
      CommandManager.setup(@bot, @data)
      @monitor = Monitor.new(@bot, @data)
      at_exit { @bot.stop }
    end

    # Connects the Discord bot to the gateway, starts the background monitoring
    # thread, and begins processing events in a blocking manner.
    #
    # @return [void]
    def start
      puts 'Seventeen Notify Discord Bot started.'
      @monitor.start
      @bot.run
    end
  end
end
