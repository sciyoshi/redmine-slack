require 'httpclient'

class SlackListener < Redmine::Hook::Listener

	def initialize
		@slack_username_custom_field = UserCustomField.find_by_name("Slack Username")
	end

	def controller_issues_new_after_save(context={})
		issue = context[:issue]

		channel = channel_for_project issue.project
		url = url_for_project issue.project

		return unless channel and url
		return if issue.is_private?

		mentions = build_mentions(issue.assigned_to, issue.description, issue.project.identifier)
		msg = "[#{escape issue.project}] #{escape issue.author} created <#{object_url issue}|#{escape issue}>#{mentions}"

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

		attachment[:fields] << {
			:title => I18n.t("field_watcher"),
			:value => escape(issue.watcher_users.join(', ')),
			:short => true
		} if Setting.plugin_redmine_slack['display_watchers'] == 'yes'

		speak msg, channel, attachment, url
	end

	def controller_issues_edit_after_save(context={})
		issue = context[:issue]
		journal = context[:journal]

		channel = channel_for_project issue.project
		url = url_for_project issue.project

		return unless channel and url and Setting.plugin_redmine_slack['post_updates'] == '1'
		return if issue.is_private?
		return if journal.private_notes?

		assignee_user = get_assignee_user journal
		mentions = build_mentions(assignee_user, journal.notes, issue.project.identifier)
		msg = "[#{escape issue.project}] #{escape journal.user.to_s} updated <#{object_url issue}#change-#{journal.id}|#{escape issue}>#{mentions}"

		attachment = {}
		attachment[:text] = escape journal.notes if journal.notes
		attachment[:fields] = journal.details.map { |d| detail_to_field d }

		speak msg, channel, attachment, url
	end

	def model_changeset_scan_commit_for_issue_ids_pre_issue_update(context={})
		issue = context[:issue]
		journal = issue.current_journal
		changeset = context[:changeset]

		channel = channel_for_project issue.project
		url = url_for_project issue.project

		return unless channel and url and issue.save
		return if issue.is_private?

		msg = "[#{escape issue.project}] #{escape journal.user.to_s} updated <#{object_url issue}|#{escape issue}>"

		repository = changeset.repository

		if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
			host, port, prefix = $2, $4, $5
			revision_url = Rails.application.routes.url_for(
				:controller => 'repositories',
				:action => 'revision',
				:id => repository.project,
				:repository_id => repository.identifier_param,
				:rev => changeset.revision,
				:host => host,
				:protocol => Setting.protocol,
				:port => port,
				:script_name => prefix
			)
		else
			revision_url = Rails.application.routes.url_for(
				:controller => 'repositories',
				:action => 'revision',
				:id => repository.project,
				:repository_id => repository.identifier_param,
				:rev => changeset.revision,
				:host => Setting.host_name,
				:protocol => Setting.protocol
			)
		end

		attachment = {}
		attachment[:text] = ll(Setting.default_language, :text_status_changed_by_changeset, "<#{revision_url}|#{escape changeset.comments}>")
		attachment[:fields] = journal.details.map { |d| detail_to_field d }

		speak msg, channel, attachment, url
	end

	def controller_wiki_edit_after_save(context = { })
		return unless Setting.plugin_redmine_slack['post_wiki_updates'] == '1'

		project = context[:project]
		page = context[:page]

		user = page.content.author
		project_url = "<#{object_url project}|#{escape project}>"
		page_url = "<#{object_url page}|#{page.title}>"
		comment = "[#{project_url}] #{page_url} updated by *#{user}*"

		channel = channel_for_project project
		url = url_for_project project

		attachment = nil
		if not page.content.comments.empty?
			attachment = {}
			attachment[:text] = "#{escape page.content.comments}"
		end

		speak comment, channel, attachment, url
	end

	def speak(msg, channel, attachment=nil, url=nil)
		url = Setting.plugin_redmine_slack['slack_url'] if not url
		username = Setting.plugin_redmine_slack['username']
		icon = Setting.plugin_redmine_slack['icon']

		params = {
			:text => msg,
			:link_names => 1,
		}

		params[:username] = username if username
		params[:channel] = channel if channel

		params[:attachments] = [attachment] if attachment

		if icon and not icon.empty?
			if icon.start_with? ':'
				params[:icon_emoji] = icon
			else
				params[:icon_url] = icon
			end
		end

		begin
			client = HTTPClient.new
			client.ssl_config.cert_store.set_default_paths
			client.ssl_config.ssl_version = :auto
			client.post_async url, {:payload => params.to_json}
		rescue Exception => e
			Rails.logger.warn("cannot connect to #{url}")
			Rails.logger.warn(e)
		end
	end

private
	def escape(msg)
		msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
	end

	def object_url(obj)
		if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
			host, port, prefix = $2, $4, $5
			Rails.application.routes.url_for(obj.event_url({
				:host => host,
				:protocol => Setting.protocol,
				:port => port,
				:script_name => prefix
			}))
		else
			Rails.application.routes.url_for(obj.event_url({
				:host => Setting.host_name,
				:protocol => Setting.protocol
			}))
		end
	end

	def url_for_project(proj)
		return nil if proj.blank?

		cf = ProjectCustomField.find_by_name("Slack URL")

		return [
			(proj.custom_value_for(cf).value rescue nil),
			(url_for_project proj.parent),
			Setting.plugin_redmine_slack['slack_url'],
		].find{|v| v.present?}
	end

	def channel_for_project(proj)
		return nil if proj.blank?

		cf = ProjectCustomField.find_by_name("Slack Channel")

		val = [
			(proj.custom_value_for(cf).value rescue nil),
			(channel_for_project proj.parent),
			Setting.plugin_redmine_slack['channel'],
		].find{|v| v.present?}

		# Channel name '-' is reserved for NOT notifying
		return nil if val.to_s == '-'
		val
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
			if key == "parent"
				title = I18n.t "field_#{key}_issue"
			else
				title = I18n.t "field_#{key}"
			end
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
		when "category"
			category = IssueCategory.find(detail.value) rescue nil
			value = escape category.to_s
		when "assigned_to"
			user = User.find(detail.value) rescue nil
			value = escape user.to_s
		when "fixed_version"
			version = Version.find(detail.value) rescue nil
			value = escape version.to_s
		when "attachment"
			attachment = Attachment.find(detail.prop_key) rescue nil
			value = "<#{object_url attachment}|#{escape attachment.filename}>" if attachment
		when "parent"
			issue = Issue.find(detail.value) rescue nil
			value = "<#{object_url issue}|#{escape issue}>" if issue
		end

		value = "-" if value.empty?

		result = { :title => title, :value => value }
		result[:short] = true if short
		result
	end

	def to_slack_usernames(usernames, project_id)
		return [] if usernames.empty?

		slack_usernames = usernames.map { |username| find_slack_username(username, project_id) }
		slack_usernames.select { |n| n.present? }
	end

	def find_slack_username(redmine_user, project_id)
		return nil if redmine_user.nil?

		if redmine_user.is_a? User
			user = redmine_user
		else
			user = User.find_by_login(redmine_user)
		end

		if user.present?
			val = user.custom_value_for(@slack_username_custom_field).value rescue nil
			if val.nil?
				return val
			end

			result = nil
			slack_usernames = val.split(/\s?,\s*/)
			slack_usernames.each { |n|
				if n.include? ':'
					proj_id, slack_username = n.split(':')
					if project_id == proj_id
						if slack_username != '-'
							result = slack_username
						else
							result = nil
						end
						break
					end
				elsif n != '-'
					result = n
				end
			}
			result
		end
	end

	def extract_usernames text = ''
		# Extracts the @xxxxx from the given text and returns a list of usernames (only xxxxx parts)

		if text.nil?
			text = ''
		end

		text.scan(/@[a-z0-9][a-z0-9_\-.]*/).uniq.each do |username|
			# Remove the leading @
			username.slice!(0)
		end
	end

	def get_assignee_user(journal)
		assignee_detail = journal.details.find do |detail|
			detail.prop_key.to_s.sub('_id', '') == 'assigned_to'
		end
		if assignee_detail.present?
			User.find(assignee_detail.value) rescue nil
		end
	end

	def build_mentions(assignee_user, text, project_id)
		# Get the assignee's Redmine User instance
		assignee_slack_username = find_slack_username(assignee_user, project_id)

		# Retrieve the mentioned Redmine usernames from the given text
		mentioned_usernames = extract_usernames text
		slack_usernames = to_slack_usernames(mentioned_usernames, project_id)

		if assignee_slack_username.present?
			slack_usernames << assignee_slack_username
		end

		# Slack usernames to be mentioned
		slack_usernames = slack_usernames.uniq.map { |name| '@' + name }
		slack_usernames.present? ? "\n" + slack_usernames.join(' ') : nil
	end
end
