require 'httpclient'

class SlackListener < Redmine::Hook::Listener
	def controller_issues_new_after_save(context={})
		issue = context[:issue]

		msg = "[#{escape issue.project}] #{escape issue.author} created <#{object_url issue}|#{escape issue}>"

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

		msg = "[#{escape issue.project}] #{escape journal.user.to_s} updated <#{object_url issue}|#{escape issue}>"

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
		msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
	end

	def object_url(obj)
		Rails.application.routes.url_for(obj.event_url :host => Setting.host_name)
	end

	def detail_to_field(detail)
		if detail.property == "cf"
			key = CustomField.find(detail.prop_key).name rescue nil
			title = key
		elsif detail.property == "attachment"
			key = "attachment"
			title = I18n.t :label_attachment
		else
			key = detail.prop_key.to_s.sub("_id", "")
			title = I18n.t "field_#{key}"
		end

		short = true
		value = escape detail.value.to_s

		case key
		when "title", "subject", "description"
			short = false
		when "tracker"
			tracker = Tracker.find(detail.value) rescue nil
			value = escape tracker.to_s
		when "project"
			project = Project.find(detail.value) rescue nil
			value = escape project.to_s
		when "status"
			status = IssueStatus.find(detail.value) rescue nil
			value = escape status.to_s
		when "priority"
			priority = IssuePriority.find(detail.value) rescue nil
			value = escape priority.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		when "fixed_version"
			version = Version.find(detail.value) rescue nil
			value = escape version.to_s
		when "attachment"
			attachment = Attachment.find(detail.prop_key) rescue nil
			value = "<#{object_url attachment}|#{escape attachment.filename}>" if attachment
		end

		value = "-" if value.empty?

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end
end
