# Seventeen Notify Discord Bot

A Discord bot for [17LIVE](https://17.live) stream notifications.

## Installation

1. Create an application on [Discord Developer Portal](https://discord.com/developers/applications/) with the following configuration.

- Installation:
  - Default Install Settings:
    - Guild Install
      - Scopes: `bot`
      - Permissions: `Send Messages`

2. Clone this repository.

```sh
git clone https://github.com/c910335/seventeen-notify-discord-bot.git
cd seventeen-notify-discord-bot
```

3. Install the dependencies.

```sh
bundle install
```

4. Edit the configuration file.

```sh
cp config.sample.rb config.rb
vim config.rb
```

## Usage

1. Run the bot.

```sh
ruby main.rb
```

2. Install the bot via the install link from [Discord Developer Portal](https://discord.com/developers/applications/).

3. Talk to the bot on Discord with the following commands and their parameters.

## Commands

- `/subscribe`: Subscribe to a 17LIVE stream for the current channel.
  - `stream_id` (Integer): The ID of the 17LIVE stream to be notified here. A stream ID can be found in the URL of the liver's profile (e.g., `https://17.live/zh-Hant/profile/#{stream_id}`).
  - `message` (String): The message to send to the current channel when the 17LIVE stream starts.
  - `mention` (Mentionable): The user or role to notify.
  - `overwrite` (Boolean): Whether to overwrite the existing subscription.
- `/unsubscribe`: Unsubscribe from a 17LIVE stream for the current channel.
  - `stream_id` (Integer): The ID of the 17LIVE stream to unsubscribe from here.
- `/test`: Trigger a test notification to the current channel.
  - `stream_id` (Integer): The ID of the 17LIVE stream to send a test notification here.
  - `silent` (Boolean): If true, the test notification will be visible only to you.
- `/list`: List the subscriptions for the current channel.

## Contributing

1. Fork it (<https://github.com/c910335/seventeen-notify-discord-bot/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Tatsujin Chin](https://github.com/c910335) - creator and maintainer
