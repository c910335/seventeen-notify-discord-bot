# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The Data class manages the in-memory storage and file persistence of stream subscriptions.
  # It provides thread-safe disk writing and delegates Hash-like access methods.
  class Data
    # The file where subscription data is persisted.
    DATA_FILE_NAME = 'data.json'

    extend Forwardable

    # @!method [](key)
    #   Retrieves a subscription.
    # @!method []=(key, value)
    #   Stores a subscription.
    # @!method delete(key)
    #   Deletes a subscription.
    # @!method values
    #   Returns an array of all subscriptions.
    def_delegators :@subscriptions, :[], :[]=, :delete, :values

    # Initializes the data store. Sets up a Mutex for thread safety and attempts
    # to restore existing subscriptions from the local JSON file.
    #
    # @return [void]
    def initialize
      @mutex = Mutex.new
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
    def save
      @mutex.synchronize do
        Tempfile.create(DATA_FILE_NAME, File.dirname(DATA_FILE_NAME)) do |temp_file|
          temp_file.write(@subscriptions.values.to_json)
          temp_file.flush
          File.rename(temp_file.path, DATA_FILE_NAME)
        end
      end
      puts 'Data saved.'
    end
  end
end
