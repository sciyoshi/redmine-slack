# frozen_string_literal: true

module RedmineSlack
  module IssuePatch
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.class_eval do
        after_create :create_from_issue
        after_save :save_from_issue
      end
    end

    module ClassMethods
    end

    module InstanceMethods
      def create_from_issue
        @create_already_fired = true
        Redmine::Hook.call_hook(:redmine_slack_issues_new_after_save, { issue: self })
        true
      end

      def save_from_issue
        if !@create_already_fired && !current_journal.nil?
          Redmine::Hook.call_hook(:redmine_slack_issues_edit_after_save,
                                  { issue: self, journal: current_journal })
        end
        true
      end
    end
  end
end
