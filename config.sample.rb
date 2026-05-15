# frozen_string_literal: true

module SeventeenNotifyDiscordBot
  # The Config module holds the configuration constants for the bot.
  # Rename this file to `config.rb` and set your variables.
  module Config
    # The Discord token of the bot from https://discord.com/developers/applications.
    DISCORD_TOKEN = 'your.discord.token.here'

    # The ID of the channel the bot will send error messages to.
    ADMIN_CHANNEL_ID = 1_234_567_890

    # A hash mapping of predefined notification message templates.
    # The `then` block transforms the array into a hash where keys and values are identical.
    NOTIFICATION_MESSAGE_TEMPLATES = [
      '注意！%<display_name>s 的直播 %<caption>s 已經開始了！感謝你的注意！',
      '快看！%<display_name>s 開播啦！%<caption>s'
    ].then { |templates| templates.zip(templates).to_h }
  end
end
