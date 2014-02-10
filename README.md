# Slack chat plugin for Redmine

This plugin posts updates to issues in your Redmine installation to a Slack
channel. Improvements are welcome! Just send a pull request.

## Screenshot

![screenshot](https://raw.github.com/sciyoshi/redmine-slack/gh-pages/screenshot.png)

## Installation

From your Redmine plugins directory, clone this repository as `redmine_slack`:

    git clone https://github.com/sciyoshi/redmine-slack.git redmine_slack

Restart Redmine, and you should see the plugin show up in the Plugins page.
Under the configuration options, set the Slack API URL to the URL for an
Incoming WebHook integration in your Slack account.

For more information, see http://www.redmine.org/projects/redmine/wiki/Plugins.
