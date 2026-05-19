# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The Monitor class handles background polling of the 17LIVE API.
  # It periodically checks all subscriptions, triggers Discord notifications,
  # and prompts the Data layer to save if statuses are updated.
  class Monitor
    # The time (in seconds) between each overall API polling loop.
    HEARTBEAT_DELAY_SECONDS = 120

    # The time (in seconds) to wait between checking individual subscriptions to avoid rate limits.
    CHECK_START_DELAY_SECONDS = 5

    # Initializes the Monitor with bot and data dependencies.
    #
    # @param bot [Discordrb::Bot] The Discord bot instance to send notifications through.
    # @param data [Data] The Data store instance holding current subscriptions.
    def initialize(bot, data)
      @bot = bot
      @data = data
    end

    # Kicks off a separate thread that periodically polls the 17LIVE API for stream status changes.
    #
    # @return [void]
    def start
      Thread.new do
        loop do
          begin
            heartbeat
          rescue StandardError => e
            puts e.full_message
            @bot.send_message(Config::ADMIN_CHANNEL_ID, e.full_message)
          end
          sleep HEARTBEAT_DELAY_SECONDS
        end
      end
    end

    # Executes a single polling cycle. Updates all subscriptions, triggers notifications
    # if a stream has started, and saves data if any statuses changed.
    #
    # @return [void]
    def heartbeat
      puts 'Heartbeat started.'
      updated = false
      subscriptions = @data.values
      subscriptions.each do |subscription|
        subscription.update!
        updated ||= subscription.updated?
        notify(subscription) if subscription.start?
        sleep CHECK_START_DELAY_SECONDS
      end
      @data.save if updated
      puts 'Heartbeat done.'
    end

    # Dispatches a Discord message for a stream event.
    #
    # @param subscription [Subscription] The target subscription to notify for.
    # @return [void]
    def notify(subscription)
      puts(
        "#{subscription.display_name} just started streaming. " \
        "Sending notification to #{subscription.channel_server_id}"
      )
      @bot.send_message(
        subscription.channel_id,
        subscription.formatted_linked_message
      )
    end
  end
end
