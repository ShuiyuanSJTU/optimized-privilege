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

  TopicsBulkAction.register_operation("open") do
    topics.each do |t|
      if guardian.can_moderate?(t)
        t.update_status('closed', false, @user)
        @changed_ids << t.id
      end
    end
  end

  TopicsBulkAction.register_operation("unarchive") do
    topics.each do |t|
      if guardian.can_moderate?(t)
        t.update_status('archived', false, @user)
        @changed_ids << t.id
      end
    end
  end

  module OverridingTopic
    def update_status(status, enabled, user, opts = {})
      super
      if status == 'closed' && enabled
        self.custom_fields['closed_by'] = user.id
        self.save_custom_fields
      end
    end

    def add_moderator_post(user, text, opts = nil)
      opts ||= {}
      new_post = nil
      creator = PostCreator.new(user,
                              raw: text,
                              post_type: opts[:post_type] || Post.types[:moderator_action],
                              action_code: opts[:action_code],
                              no_bump: opts[:bump].blank?,
                              topic_id: self.id,
                              silent: opts[:silent],
                              skip_validations: true,
                              skip_guardian: true,
                              custom_fields: opts[:custom_fields],
                              import_mode: opts[:import_mode])

      if (new_post = creator.create) && new_post.present?
        increment!(:moderator_posts_count) if new_post.persisted?
        new_post.update!(post_number: opts[:post_number], sort_order: opts[:post_number]) if opts[:post_number].present?

        TopicLink.extract_from(new_post)
        QuotedPost.extract_from(new_post)
      end

      new_post
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
        if is_my_own?(topic) && (!topic.closed || (topic.closed && topic.custom_fields['closed_by'] == @user&.id))
          # 自己的话题：自己可以关闭，或者打开被自己关的
          return true
        end
          false
      else super
      end
    end

    def affected_by_slow_mode?(topic)
      topic&.slow_mode_seconds.to_i > 0 && @user.human? &&
      !(is_staff? || @user.has_trust_level?(TrustLevel[4]))
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

  module OverridePostGuardian
    def can_view_edit_history?(post)
      return false unless post

      if !post.hidden
        return true if post.wiki || SiteSetting.edit_history_visible_to_public
      end

      authenticated? &&
      (is_staff? || @user.has_trust_level?(TrustLevel[4]) || @user.id == post.user_id) &&
      can_see_post?(post)
    end
  end

  class ::Guardian
    prepend OverridingTopicGuardian
    prepend OverrideUserGuardian
    prepend OverridePostGuardian
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
