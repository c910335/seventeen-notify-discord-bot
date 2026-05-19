# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The CommandManager handles the registration and execution of Discord slash commands.
  # It acts as the controller bridging Discord interactions with internal data logic.
  class CommandManager
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

    # Convenience method to instantiate and immediately setup commands.
    #
    # @param bot [Discordrb::Bot] The Discord bot instance.
    # @param data [Data] The data storage instance.
    # @return [void]
    def self.setup(*, **)
      new(*, **).setup
    end

    # Initializes the command manager with required dependencies.
    #
    # @param bot [Discordrb::Bot] The Discord bot instance.
    # @param data [Data] The data storage instance.
    def initialize(bot, data)
      @bot = bot
      @data = data
    end

    # Registers all application commands and autocomplete handlers with Discord.
    #
    # @return [void]
    def setup
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

    # Handler for the `/subscribe` command. Sets up a new stream notification.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event data.
    # @return [void]
    def subscribe(event)
      message = construct_notification_message(event)
      return unless message

      subscription = temp_subscription(event, message)
      if (existing_subscription = @data[subscription.lookup_key])
        if event.options['overwrite']
          existing_subscription.message = message
          subscription_enabled(event, existing_subscription)
          @data.save
          return
        end

        already_subscribed(event, existing_subscription)
        return
      end

      subscription.update!
      @data[subscription.lookup_key] = subscription
      subscription_enabled(event, subscription)
      @data.save
    end

    # Handler for the `/unsubscribe` command. Removes a given stream from the channel's alerts.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event data.
    # @return [void]
    def unsubscribe(event)
      unsubscription = temp_subscription(event)
      if (subscription = @data[unsubscription.lookup_key])
        @data.delete(subscription.lookup_key)
        event.respond(
          content: format(
            UNSUBSCRIBED_MESSAGE_TEMPLATE,
            display_name: subscription.display_name,
            profile_link: subscription.profile_link
          ),
          ephemeral: true
        )
        @data.save
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
      if (subscription = @data[test_subscription.lookup_key])
        puts "Trigger a test notification for #{subscription.display_name} to #{subscription.channel_server_id}"
        event.respond(
          content: subscription.formatted_linked_message,
          ephemeral: event.options['silent']
        )
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
          content: content,
          ephemeral: true,
          flags: Discordrb::Message::FLAGS[:suppress_embeds]
        )
      end
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
    end

    # Retrieves all subscriptions assigned strictly to the channel the event originated from.
    #
    # @param event [Discordrb::Events::ApplicationCommandEvent] The interaction event.
    # @return [Array<Subscription>] A list of subscriptions associated with the channel.
    def subscriptions_here(event)
      @data.values.select do |subscription|
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
