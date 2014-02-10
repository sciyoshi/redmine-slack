require 'httpclient'

class SlackListener < Redmine::Hook::Listener
	def controller_issues_bulk_edit_after_save(context={})
		issue = context[:issue]
		speak context[:issue].id
	end

	def controller_issues_new_after_save(context={})
		issue = context[:issue]

		msg = "[#{escape issue.project}] #{escape issue.author} created <#{issue_url issue}|#{escape issue}>"

		attachment = {}
		attachment[:text] = escape issue.description if issue.description
		attachment[:fields] = [{
			:title => I18n.t("field_status"),
			:value => escape(issue.status.to_s),
			:short => true
		}, {
			:title => I18n.t("field_priority"),
			:value => escape(issue.priority.to_s),
			:short => true
		}, {
			:title => I18n.t("field_assigned_to"),
			:value => escape(issue.assigned_to.to_s),
			:short => true
		}]

		speak msg, attachment
	end

	def controller_issues_edit_after_save(context={})
		issue = context[:issue]
		journal = context[:journal]

		msg = "[#{escape issue.project}] #{escape issue.author} updated <#{issue_url issue}|#{escape issue}>"

		attachment = {}
		attachment[:text] = escape journal.notes if journal.notes
		attachment[:fields] = journal.details.map { |d| detail_to_field d }

		speak msg, attachment
	end

	def speak(msg, attachment=nil)
		url = Setting.plugin_redmine_slack[:slack_url]
		username = Setting.plugin_redmine_slack[:username]
		channel = Setting.plugin_redmine_slack[:channel]

		params = {
			:text => msg
		}

		params[:username] = username if username
		params[:channel] = channel if channel

		params[:attachments] = [attachment] if attachment

		client = HTTPClient.new
		client.ssl_config.cert_store.set_default_paths
		client.post url, {:payload => params.to_json}
	end

private
	def escape(msg)
		CGI::escapeHTML msg.to_s
	end

	def issue_url(issue)
		Rails.application.routes.url_for(issue.event_url :host => Setting.host_name)
	end

	def detail_to_field(detail)
		key = detail.prop_key.sub "_id", ""

		title = I18n.t "field_#{key}"

		short = true
		value = escape detail.value.to_s

		case key
		when "title", "subject"
			short = false
		when "status"
			user = IssueStatus.find(detail.value) rescue nil
			value = escape user.to_s
		when "priority"
			user = IssuePriority.find(detail.value) rescue nil
			value = escape user.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		end

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end
end
