# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The Subscription struct represents a stream subscription for a specific Discord channel.
  # It tracks stream metadata, status, and custom user messages.
  Subscription = Struct.new(
    :stream_id,
    :channel_id,
    :server_id,
    :message,
    :status,
    :last_status,
    :display_name,
    :caption,
    :updated
  ) do
    # Fetches the latest info from the API, compares it to the current state,
    # and updates the struct fields if necessary.
    #
    # @return [void]
    def update!
      self.last_status = status
      self.updated = false
      info.each_pair do |k, v|
        next if self[k] == v

        puts "#{display_name || 'A new subscription'}'s #{k} just changed: #{self[k]} => #{v}."
        self[k] = v
        self.updated = true
      end
    end

    # Requests the latest stream status and user info from the 17LIVE API.
    #
    # @return [Hash] A hash containing `:status`, `:caption`, and `:display_name`.
    def info
      json_info = JSON.parse(Net::HTTP.get(URI(api_link)))
      {
        status: json_info['status'],
        caption: json_info['caption'],
        display_name: json_info['userInfo']['displayName']
      }
    end

    # Formats a unique identifier combining the channel ID and server ID.
    #
    # @return [String] A formatted ID string (e.g. "channel123:server456").
    def channel_server_id
      server_part = if server_id
                      ":#{server_id}"
                    else
                      ''
                    end
      "#{channel_id}#{server_part}"
    end

    # Determines if the stream has just started based on status transitions.
    # Status > 1 generally indicates streaming, while <= 1 indicates offline/ended.
    #
    # @return [Boolean] true if the stream transitioned from offline to online.
    def start? = last_status && last_status <= 1 && status > 1

    # Returns the formatted endpoint to poll for a specific stream ID.
    #
    # @return [String] The API URL to fetch live stream info.
    def api_link = format('https://wap-api.17app.co/api/v1/lives/%d/info', stream_id)

    # Returns the web URL of the liver's profile on 17LIVE.
    #
    # @return [String] The URL of the liver's profile.
    def profile_link = format('https://17.live/zh-Hant/profile/%d', stream_id)

    # Returns the web URL to directly watch the live stream.
    #
    # @return [String] The direct URL to the live stream.
    def stream_link = format('https://17.live/zh-Hant/live/%d', stream_id)

    # Formats the custom notification message using the struct's current values.
    #
    # @return [String] The formatted text message.
    def formatted_message = format(message, **to_h)

    # Prepends the stream link to the formatted message.
    #
    # @return [String] The final notification payload for Discord.
    def formatted_linked_message = "#{stream_link}\n#{formatted_message}"

    # Checks if any properties of the subscription were changed during the last update.
    #
    # @return [Boolean] Returns true if the subscription had an update in the last check.
    def updated? = updated

    # Generates a unique key for Hash lookups based on its identity.
    #
    # @return [Array<Integer, Integer, Integer>] An array containing stream_id, channel_id, and server_id.
    def lookup_key = [stream_id, channel_id, server_id]

    # Converts the struct into JSON format for persistence.
    #
    # @param args [Array] Optional arguments passed to `to_json`.
    # @return [String] The JSON representation of the struct.
    def to_json(*) = to_h.to_json(*)

    # String representation of the subscription suitable for listing to users.
    #
    # @return [String] The display name, profile link, and custom message format.
    def to_s = "- #{display_name} (#{profile_link}): #{formatted_message}"
  end
end
