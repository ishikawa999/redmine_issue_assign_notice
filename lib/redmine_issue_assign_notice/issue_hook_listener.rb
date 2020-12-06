module RedmineIssueAssignNotice

  class IssueHookListener < Redmine::Hook::Listener

    def initialize
      @client = NoticeClient.new
      Rails.logger.debug "IssueHookListener#initialize"
    end

    def redmine_issue_assign_notice_new(context={})
      issue = context[:issue]

      Rails.logger.debug "IssueHookListener#redmine_issue_assign_notice_new issue_id:#{issue.id}"

      if issue.assigned_to.nil? 
        return
      end

      notice(issue: issue, new_assgined_to: issue.assigned_to, note: issue.description)
    end

    def redmine_issue_assign_notice_change(context={})
      issue = context[:issue]
      journal = context[:journal]

      Rails.logger.debug "IssueHookListener#redmine_issue_assign_notice_change issue_id:#{issue.id}"

      assign_journal = journal.details.find{ |detail| detail.property == 'attr' && detail.prop_key == 'assigned_to_id' }
      if assign_journal.nil? 
        return
      end

      old_assgined_to = User.find(assign_journal.old_value.to_i) unless assign_journal.old_value.nil?
      new_assgined_to = User.find(assign_journal.value.to_i) unless assign_journal.value.nil?

      notice(issue: issue, old_assgined_to: old_assgined_to, new_assgined_to: new_assgined_to, note: journal.notes)
    end

    private

    def notice(issue:, old_assgined_to: nil, new_assgined_to:, note:)

      if Setting.plugin_redmine_issue_assign_notice['notice_url'].blank?
        return
      end

      message = create_message(issue, old_assgined_to, new_assgined_to, note)

      Rails.logger.debug "IssueHookListener#notice message:#{message}"

      @client.notice(message, Setting.plugin_redmine_issue_assign_notice['notice_url'])
    end

    def create_message(issue, old_assgined_to, new_assgined_to, note)

      message = "#{mention new_assgined_to}"
      message << " " if message.length > 0
      message << "Assign changed from #{user_name old_assgined_to} to #{user_name new_assgined_to}"
      message << "\n"
      message << "[#{escape issue.project}] <#{issue_url issue}|#{escape issue.tracker} ##{issue.id}> #{issue.subject} (#{escape issue.status})"
      message << "\n"
      message << trimming(note)
    end

    def mention(user)

      if user.nil? || Setting.plugin_redmine_issue_assign_notice['mention_to_assignee'] != '1'
        return nil
      end

      noteice_field = user.custom_field_values.find{ |field| field.custom_field.name == 'Assign Notice ID' }
      if noteice_field.nil? || noteice_field.value.blank?
        return nil
      end

      if slack?
        "<@#{noteice_field.value}>"
      else
        "@#{noteice_field.value}"
      end
    end

    def user_name(user)
      if user.nil?
        '_[none]_'
      else
        "_#{escape user}_"
      end
    end

    def issue_url(issue)
      "#{Setting.protocol}://#{Setting.host_name}/issues/#{issue.id}"
    end

    def escape(msg)
      msg.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
    end

    def trimming(note)
      if note.nil?
        return nil
      end

      flat = note.gsub(/\r\n|\n|\r/, ' ')
      if flat.length > 200
        flat[0, 200] + '...'
      else
        flat
      end
    end

    def slack?
      Setting.plugin_redmine_issue_assign_notice['notice_url'].include? 'slack.com/'
    end
  end
end