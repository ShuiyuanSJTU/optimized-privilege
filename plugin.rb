# frozen_string_literal: true

# name: optimized privilege
# about:
# version: 0.0.1
# authors: Jiajun Du
# url: https://github.com/ShuiyuanSJTU/optimized-privilege
# required_version: 2.7.0
# transpile_js: true

enabled_site_setting :optimized_privilege_enabled

PLUGIN_NAME ||= 'OptimizedPrivilege'


after_initialize do

  Topic.register_custom_field_type 'closed_by', :integer
  User.register_custom_field_type 'last_changed_username', :datetime

  TopicQuery.add_custom_filter(:closed) do |results, topic_query|
    if topic_query.options[:closed]
      results = results.where(closed: topic_query.options[:closed])
    end
    results
  end

  TopicQuery.add_custom_filter(:archived) do |results, topic_query|
    if topic_query.options[:archived]
      results = results.where(archived: topic_query.options[:archived])
    end
    results
  end

  module OverridingTopic
    def update_status(status, enabled, user, opts = {})
      super
      if status == 'closed' && enabled
        self.custom_fields['closed_by'] = user.id
        self.save_custom_fields
      end
    end
  end

  class ::Topic
    prepend OverridingTopic
  end

  module OverridingTopicViewDetailsSerializer
    def include_can_close_topic?
      scope.can_close_topic?(object.topic)
    end
  end

  class ::TopicViewDetailsSerializer
    prepend OverridingTopicViewDetailsSerializer
  end

  module OverridingTopicGuardian
    def can_close_topic?(topic)
      if SiteSetting.optimized_can_close_topic
        return true if super
        if !topic.closed || (topic.closed && topic.custom_fields['closed_by'] == @user&.id)
          # 只能打开自己关的
          return true 
        end
          false
      else super
      end
    end
  end

  module OverrideUserGuardian
    def can_edit_username?(user)
      if SiteSetting.optimized_change_username
        return false if SiteSetting.auth_overrides_username?
          return true if is_staff?
          return false if is_anonymous?
          is_me?(user)
      else super
      end
      end
  end

  class ::Guardian
    prepend OverridingTopicGuardian
    prepend OverrideUserGuardian
  end

  class ::UsersController
    before_action :check_change_username_limit, only: [:username]
    after_action :add_change_username_limit, only: [:username]
    def check_change_username_limit
      if SiteSetting.optimized_change_username && !current_user&.staff?
        old = current_user.custom_fields['last_changed_username']
        if old
          time = Time.parse(old) + SiteSetting.optimized_username_change_period * 86400
            if Time.now < time
              render json: { success: false, message: "正处于更名间隔期，请于#{time.strftime("%Y-%m-%d %H:%M:%S %Z")}之后再尝试！" }, status: 403
            end
        end
      end
    end

    def add_change_username_limit
      if SiteSetting.optimized_change_username
        current_user.custom_fields['last_changed_username'] = Time.now
        current_user.save_custom_fields
      end
    end
  end


end
