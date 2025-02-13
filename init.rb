# frozen_string_literal: true

require 'redmine'

require File.expand_path('../lib/redmine_slack/listener', __FILE__)

Redmine::Plugin.register :redmine_slack do
  name 'Redmine Slack'
  author 'Samuel Cormier-Iijima'
  url 'https://github.com/sciyoshi/redmine-slack'
  author_url 'http://www.sciyoshi.com'
  description 'Slack chat integration'
  version '0.2'

  requires_redmine version_or_higher: '0.8.0'

  settings \
    default: {
      'callback_url' => 'http://slack.com/callback/',
      'channel' => nil,
      'icon' => 'https://raw.github.com/sciyoshi/redmine-slack/gh-pages/icon.png',
      'username' => 'redmine',
      'display_watchers' => 'no'
    },
    partial: 'settings/slack_settings'
end

if Rails.version > '6.0' && Rails.autoloaders.zeitwerk_enabled?
  Rails.application.config.after_initialize do
    unless Issue.included_modules.include? RedmineSlack::IssuePatch
      Issue.include(RedmineSlack::IssuePatch)
    end
  end
else
  (Rails.version > '5' ? ActiveSupport::Reloader : ActionDispatch::Callbacks).to_prepare do
    require_dependency 'issue'
    unless Issue.included_modules.include? RedmineSlack::IssuePatch
      Issue.include(RedmineSlack::IssuePatch)
    end
  end
end
