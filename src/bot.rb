# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The Bot class initializes the Discord client, handles user commands,
  # stores subscriptions, and runs a background thread to poll stream status.
  class Bot
    # The file where subscription data is persisted.
    DATA_FILE_NAME = 'data.json'

    # The time (in seconds) between each overall API polling loop.
    HEARTBEAT_DELAY_SECONDS = 120

    # The time (in seconds) to wait between checking individual subscriptions to avoid rate limits.
    CHECK_START_DELAY_SECONDS = 5

    # Message template used when a subscription is successfully created.
    SUBSCRIPTION_ENABLED_MESSAGE_TEMPLATE = 'I will start sending notifications ' \
                                            'to <#%<channel_id>d> with this message (%<message>s) ' \
                                            'when %<display_name>s (%<profile_link>s) starts streaming.'

    # Message template used when a user successfully unsubscribes.
    UNSUBSCRIBED_MESSAGE_TEMPLATE = 'Unsubscribed from %<display_name>s (%<profile_link>s).'

    # Message template used when attempting to unsubscribe from a non-existent sub.
    SUBSCRIPTION_NOT_FOUND_MESSAGE_TEMPLATE = 'Subscription to this liver (%<profile_link>s) not found.'

    # Error message for unresolvable user or role mentions.
    MENTION_NOT_FOUND_MESSAGE = 'Channel, Role, Member, or User not found.'

    # Error message returned when a subscription already exists and overwrite is false.
    ALREADY_SUBSCRIBED_MESSAGE = 'The subscription to %<display_name>s (%<profile_link>s) already exists.'

    # Error message when attempting to list empty subscriptions.
    SUBSCRIPTIONS_NOT_FOUND_MESSAGE = 'Subscription not found.'

    # Convenience method to instantiate and run the bot.
    #
    # @return [void]
    def self.start
      new.start
    end

    # Initializes internal states, creates a mutex for thread-safe file operations,
    # loads data from the JSON file, configures the Discord bot, and fires off
    # the background heartbeat thread.
    #
    # @return [void]
    def initialize
      @data_mutex = Mutex.new
      init_data
      init_bot
      init_heartbeat
    end

    # Connects the Discord bot to the gateway and starts processing events in a blocking manner.
    #
    # @return [void]
    def start
      puts 'Seventeen Notify Discord Bot started.'
      @bot.run
    end

    # Loads the saved subscriptions from `data.json` into a Hash.
    # Creates a new Hash if the file does not exist.
    #
    # @return [void]
    def init_data
      @subscriptions = {}
      return unless File.exist? DATA_FILE_NAME

      json_data = JSON.parse File.read DATA_FILE_NAME
      json_data.each do |entry|
        subscription = Subscription.new(**entry)
        @subscriptions[subscription.lookup_key] = subscription
      end
      puts 'Data restored.'
    end

    # Serializes the current subscriptions and safely writes them to `data.json`.
    # Uses a mutex to ensure thread safety and a temporary file with an atomic
    # rename operation to prevent data corruption during the write process.
    #
    # @return [void]
    def save_data
      @data_mutex.synchronize do
        Tempfile.create(DATA_FILE_NAME, File.dirname(DATA_FILE_NAME)) do |temp_file|
          temp_file.write(@subscriptions.values.to_json)
          temp_file.flush
          File.rename(temp_file.path, DATA_FILE_NAME)
        end
      end
      puts 'Data saved.'
    end

    # Configures the underlying Discordrb client and registers application commands.
    # Ensures the bot cleans up gracefully on exit.
    #
    # @return [void]
    def init_bot
      @bot = Discordrb::Bot.new token: Config::DISCORD_TOKEN, intents: :unprivileged
      at_exit { @bot.stop }
      init_application_commands
      init_autocomplete
    end

    # Registers slash commands with the Discord API and sets up their respective handlers.
    #
    # @return [void]
    def init_application_commands
      create_application_command(:subscribe, 'Subscribe to a 17LIVE stream for the current channel.') do |cmd|
        cmd.integer(
          :stream_id,
          'The ID of the 17LIVE stream to be notified here.',
          required: true,
          autocomplete: true
        )
        cmd.string(
          :message,
          'The message to send to the current channel when the 17LIVE stream starts.',
          required: true,
          autocomplete: true
        )
        cmd.mentionable(:mention, 'The user or role to notify.')
        cmd.boolean(:overwrite, 'Whether to overwrite the existing subscription.')
      end

      create_application_command(:unsubscribe, 'Unsubscribe from a 17LIVE stream for the current channel.') do |cmd|
        cmd.integer(
          :stream_id,
          'The ID of the 17LIVE stream to unsubscribe from here.',
          required: true,
          autocomplete: true
        )
      end

      create_application_command(:test, 'Trigger a test notification to the current channel.') do |cmd|
        cmd.integer(
          :stream_id,
          'The ID of the 17LIVE stream to send a test notification here.',
          required: true,
          autocomplete: true
        )
        cmd.boolean(
          :silent,
          'If true, the test notification will be visible only to you.',
          required: true
        )
      end

      create_application_command(:list, 'List the subscriptions for the current channel.')
    end

    # Attaches autocomplete logic to specific command parameters.
    #
    # @return [void]
    def init_autocomplete
      setup_autocomplete(:message) { |*args| message_autocomplete(*args) }
      setup_autocomplete(:stream_id) { |*args| stream_id_autocomplete(*args) }
    end

    # Kicks off a separate thread that periodically polls the 17LIVE API for stream status changes.
    #
    # @return [void]
    def init_heartbeat
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
      subscriptions_snapshot = @subscriptions.values
      subscriptions_snapshot.each do |subscription|
        subscription.update!
        updated ||= subscription.updated?
        notify(subscription) if subscription.start?
        sleep CHECK_START_DELAY_SECONDS
      end
      save_data if updated
      puts 'Heartbeat done.'
    end

    # Dispatches a Discord message for a stream event.
    #
    # @param subscription [Subscription] The target subscription to notify for.
    # @param test_event [Discordrb::Events::ApplicationCommandEvent, nil] The event to reply to if this is a test.
    # @param silent [Boolean] Whether the test notification should be ephemeral (only visible to the command user).
    # @return [void]
    def notify(subscription, test_event = nil, silent: false)
      if test_event
        puts(
          "Trigger a test notification for #{subscription.display_name} " \
          "to #{subscription.channel_server_id}"
        )
        test_event.respond(
          content: subscription.formatted_linked_message,
          ephemeral: silent
        )
      else
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

    # Registers an application command and routes its invocation to the proper handler method.
    #
    # @param name [Symbol] The name of the command.
    # @param description [String] A brief explanation of the command's purpose.
    # @yieldparam cmd [Discordrb::Commands::ApplicationCommandBuilder] The command builder object.
    # @return [void]
    def create_application_command(name, description, &)
      @bot.register_application_command(name, description, default_member_permissions: '0', &)
      @bot.application_command(name) do |event|
        log_application_command(event)
        send(name, event)
      end
      puts "Application command /#{name} created."
    end

    # Handler for the `/subscribe` command. Sets up a new stream notification.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event data.
    # @return [void]
    def subscribe(event)
      message = construct_notification_message(event)
      return unless message

      subscription = temp_subscription(event, message)
      if (existing_subscription = @subscriptions[subscription.lookup_key])
        if event.options['overwrite']
          existing_subscription.message = message
          subscription_enabled(event, existing_subscription)
          return
        end

        already_subscribed(event, existing_subscription)
        return
      end

      subscription.update!
      @subscriptions[subscription.lookup_key] = subscription
      subscription_enabled(event, subscription)
    end

    # Handler for the `/unsubscribe` command. Removes a given stream from the channel's alerts.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event data.
    # @return [void]
    def unsubscribe(event)
      unsubscription = temp_subscription(event)
      if (subscription = @subscriptions[unsubscription.lookup_key])
        @subscriptions.delete(subscription.lookup_key)
        event.respond(
          content: format(
            UNSUBSCRIBED_MESSAGE_TEMPLATE,
            display_name: subscription.display_name,
            profile_link: subscription.profile_link
          ),
          ephemeral: true
        )
        save_data
      else
        subscription_not_found(event, unsubscription)
      end
    end

    # Handler for the `/test` command. Fires a mock notification based on existing configurations.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event data.
    # @return [void]
    def test(event)
      test_subscription = temp_subscription(event)
      if (subscription = @subscriptions[test_subscription.lookup_key])
        notify(subscription, event, silent: event.options['silent'])
      else
        subscription_not_found(event, test_subscription)
      end
    end

    # Handler for the `/list` command. Displays all current subscriptions for the originating channel.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event data.
    # @return [void]
    def list(event)
      content = subscriptions_here(event).join("\n")
      if content.empty?
        event.respond(
          content: SUBSCRIPTIONS_NOT_FOUND_MESSAGE,
          ephemeral: true
        )
      else
        event.respond(
          content: subscriptions_here(event).join("\n"),
          ephemeral: true,
          flags: Discordrb::Message::FLAGS[:suppress_embeds]
        )
      end
    end

    # Registers autocomplete handling for a specific parameter.
    #
    # @param name [Symbol] Parameter name to provide autocomplete for.
    # @yieldparam event [Discordrb::Events::AutocompleteEvent] The autocomplete event.
    # @yieldparam current_value [String] The current value typed by the user.
    # @return [void]
    def setup_autocomplete(name)
      @bot.autocomplete(name) do |event|
        current_value = event.options[name.to_s].to_s
        event.respond(choices: yield(event, current_value))
      end
      puts "Autocomplete set for #{name}."
    end

    # Provides auto-complete suggestions for the message text from the predefined config.
    #
    # @param _event [Discordrb::Events::AutocompleteEvent] The autocomplete event (unused).
    # @param current_value [String] The current value typed by the user.
    # @return [Hash<String, String>] A hash of display texts mapped to string values.
    def message_autocomplete(_event, current_value)
      Config::NOTIFICATION_MESSAGE_TEMPLATES.filter { |_k, v| v.include? current_value }
    end

    # Provides auto-complete suggestions for existing stream IDs tracked in the current channel.
    #
    # @param event [Discordrb::Events::AutocompleteEvent] The autocomplete event.
    # @param current_value [String] The current value typed by the user.
    # @return [Hash<String, Integer>] A hash of display names mapped to stream IDs.
    def stream_id_autocomplete(event, current_value)
      choices = {}
      subscriptions_here(event).each do |subscription|
        if subscription.stream_id.to_s.start_with?(current_value) || subscription.display_name.include?(current_value)
          choices[subscription.display_name] = subscription.stream_id
        end
      end
      choices
    end

    # Constructs the final payload text containing the potential mentions and main message string.
    #
    # @param subscribe_event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @return [String, nil] The fully built message string, or nil if the mention was not found.
    def construct_notification_message(subscribe_event)
      message = subscribe_event.options['message']
      return message unless subscribe_event.options.key? 'mention'

      mention = construct_mention(
        subscribe_event,
        subscribe_event.options['mention']
      )
      return unless mention

      "#{mention} #{message}"
    end

    # Attempts to locate a mentionable discord object and returns its mention tag string.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param id [String, Integer] The ID of the mentionable object.
    # @return [String, nil] The discord mention string format, or nil on failure.
    def construct_mention(event, id)
      if (mentionable = construct_mentionable(event, id))
        mentionable.mention
      else
        event.respond(MENTION_NOT_FOUND_MESSAGE)
        nil
      end
    end

    # Checks if the interaction occurred inside a server or direct message and fetches the object.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param id [String, Integer] The ID of the mentionable object.
    # @return [Discordrb::Role, Discordrb::Member, Discordrb::User, Discordrb::Channel, nil] The resolved object.
    def construct_mentionable(event, id)
      if event.server_id
        construct_server_mentionable(event, id)
      else
        event.bot.user(id)
      end
    end

    # Searches for roles, members, users, or channels in a server to tag.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param id [String, Integer] The ID of the mentionable object.
    # @return [Discordrb::Role, Discordrb::Member, Discordrb::User, Discordrb::Channel, nil] The resolved object.
    def construct_server_mentionable(event, id)
      event.server&.role(id) ||
        event.server&.member(id) ||
        event.bot.user(id) ||
        event.server&.channel(id)
    end

    # Builds a placeholder subscription used for lookups or initialization.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param message [String, nil] Optional message layout.
    # @return [Subscription] A newly constructed temporary subscription.
    def temp_subscription(event, message = nil)
      Subscription.new(
        stream_id: event.options['stream_id'],
        channel_id: event.channel.id,
        server_id: event.server_id,
        message: message
      )
    end

    # Sends a confirmation ephemeral response when a subscription is added or updated.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param subscription [Subscription] The newly created or updated subscription.
    # @return [void]
    def subscription_enabled(event, subscription)
      event.respond(
        content: format(
          SUBSCRIPTION_ENABLED_MESSAGE_TEMPLATE,
          channel_id: subscription.channel_id,
          message: subscription.formatted_message,
          display_name: subscription.display_name,
          profile_link: subscription.profile_link
        ),
        ephemeral: true
      )
      save_data
    end

    # Retrieves all subscriptions assigned strictly to the channel the event originated from.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @return [Array<Subscription>] A list of subscriptions associated with the channel.
    def subscriptions_here(event)
      @subscriptions.each_value.filter do |subscription|
        subscription.channel_id == event.channel.id &&
          subscription.server_id == event.server_id
      end
    end

    # Sends an ephemeral failure message indicating the subscription was a duplicate.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param subscription [Subscription] The duplicated subscription.
    # @return [void]
    def already_subscribed(event, subscription)
      event.respond(
        content: format(
          ALREADY_SUBSCRIBED_MESSAGE,
          display_name: subscription.display_name,
          profile_link: subscription.profile_link
        ),
        ephemeral: true
      )
    end

    # Sends an ephemeral failure message indicating the desired subscription wasn't found.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @param subscription [Subscription] The subscription that was not found.
    # @return [void]
    def subscription_not_found(event, subscription)
      event.respond(
        content: format(
          SUBSCRIPTION_NOT_FOUND_MESSAGE_TEMPLATE,
          profile_link: subscription.profile_link
        ),
        ephemeral: true
      )
    end

    # Logs executed slash commands cleanly to standard output for debugging/tracking.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event to log.
    # @return [void]
    def log_application_command(event)
      server_part = if event.server_id
                      ":#{event.server_id}"
                    else
                      ''
                    end
      puts format(
        '%<user_name>s@%<channel_id>s%<server_part>s: /%<command_name>s %<options>s',
        user_name: event.user.name,
        channel_id: event.channel_id,
        server_part: server_part,
        command_name: event.command_name,
        options: event.options.map { |pair| pair.join(': ') }.join(', ')
      )
    end
  end
end
