# frozen_string_literal: true

# name: optimized-privilege
# about:
# version: 1.0.4
# authors: Jiajun Du, pangbo
# url: https://github.com/ShuiyuanSJTU/optimized-privilege
# required_version: 2.7.0
# transpile_js: true

enabled_site_setting :optimized_privilege_enabled

PLUGIN_NAME ||= 'OptimizedPrivilege'

after_initialize do

  Topic.register_custom_field_type 'closed_by', :integer
  User.register_custom_field_type 'last_changed_username', :datetime

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
    # def add_moderator_post(user, text, opts = nil)
    #   opts ||= {}
    #   new_post = nil
    #   creator = PostCreator.new(user,
    #                           raw: text,
    #                           post_type: opts[:post_type] || Post.types[:moderator_action],
    #                           action_code: opts[:action_code],
    #                           no_bump: opts[:bump].blank?,
    #                           topic_id: self.id,
    #                           silent: opts[:silent],
    #                           skip_validations: true,
    #                           skip_guardian: true,
    #                           custom_fields: opts[:custom_fields],
    #                           import_mode: opts[:import_mode])

    #   if (new_post = creator.create) && new_post.present?
    #     increment!(:moderator_posts_count) if new_post.persisted?
    #     new_post.update!(post_number: opts[:post_number], sort_order: opts[:post_number]) if opts[:post_number].present?

    #     TopicLink.extract_from(new_post)
    #     QuotedPost.extract_from(new_post)
    #   end

    #   new_post
    # end

    # 不允许在慢速模式限制中关闭话题
    def update_status(status, enabled, user, opts = {})
      if status == 'closed' && enabled
        if Guardian.new(user).affected_by_slow_mode?(self)
          tu = TopicUser.find_by(user: user, topic: self)
          if tu&.last_posted_at
            threshold = tu.last_posted_at + self.slow_mode_seconds.seconds
            if DateTime.now < threshold
              raise Discourse::InvalidAccess.new("当前处于慢速模式，请于#{threshold.strftime("%Y-%m-%d %H:%M:%S %Z")}之后再尝试！")
            end
          end
        end
      end
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
    # https://github.com/discourse/discourse/blob/aee7197c435c44399c4bcfd6ed1c87763b726cb7/lib/guardian/topic_guardian.rb#L342
    def can_close_topic?(topic)
      if SiteSetting.optimized_can_close_topic
        return true if super
        return false if !is_my_own?(topic) # 只能操作自己的话题
        return true if !topic.closed # 自己可以关闭

        # 或者打开被自己关的（需要设置支持）
        if SiteSetting.optimized_can_open_topic_closed_by_self &&
          topic.closed && topic.custom_fields['closed_by'] == @user&.id
          return true
        end
        false
      else super
      end
    end
  end

  module OverrideUserGuardian
    # https://github.com/discourse/discourse/blob/aee7197c435c44399c4bcfd6ed1c87763b726cb7/lib/guardian/user_guardian.rb#L24
    def can_edit_username?(user)
      if SiteSetting.optimized_change_username
        return false if SiteSetting.auth_overrides_username?
          return true if is_staff?
          return false if is_anonymous?
          is_me?(user)
      else
        super
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
      (is_staff_or_tl4? || @user.id == post.user_id) &&
      can_see_post?(post)
    end

    def can_delete_post?(post)
      if post.post_type == Post.types[:small_action] && !is_staff_or_tl4?
        return false
      end
      super
    end

    def can_create_post_in_topic?(topic)
      return false if !super

      # 禁止禁言用户在私信中发言
      if @user.silenced? && !SiteSetting.optimized_silenced_can_create_post_in_private_message && topic.private_message? 
        if topic.allowed_users.length > 0 &&
          topic.allowed_users.all? {|u| is_me?(u) || u.staff?} &&
          topic.allowed_groups.all? {|g| g.staff?} &&
          (is_me?(topic.first_post.user) || topic.first_post.user.staff?)
          return true
        else 
          return false
        end
      else
        return true
      end
    end

    # 禁止禁言用户邀请用户
    def can_invite_to?(object, groups = nil)
      return false if @user.silenced? && !SiteSetting.optimized_silenced_can_invite_to
      super
    end

    # 禁止禁言用户恢复自己的帖子
    def can_recover_post?(post)
      if @user.silenced? && !SiteSetting.optimized_silenced_can_recover_post
        return false
      else
        super
      end
    end

    # 禁止禁言用户将帖子设置为 wiki
    def can_wiki?(post)
      if @user.silenced? && !SiteSetting.optimized_silenced_can_wiki_post
        return false
      else
        super
      end
    end
  end

  class ::Guardian

    def is_staff_or_tl4?
      is_staff? || @user.has_trust_level?(TrustLevel[4])
    end

    prepend OverridingTopicGuardian
    prepend OverrideUserGuardian
    prepend OverridePostGuardian
  end

  # 将用户自行删除账号改为匿名化
  module OverrideUsersController
    def destroy
      if SiteSetting.optimized_anonymous_instead_of_destroy
        @user = fetch_user_from_params
        guardian.ensure_can_delete_user!(@user)

        UserAnonymizer.make_anonymous(@user, current_user)

        render json: success_json
      else
        super
      end
    end
  end
  on :user_anonymized do |user, opts|
    user.set_automatic_groups
  end

  class ::UsersController
    prepend OverrideUsersController
    # 添加用户名更改间隔限制
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


  # 允许版主列出用户的所有警告私信，即使用户已经退出了警告
  module OverrideTopicQuery
    def list_private_messages_warnings(user)
      if @user.staff?
        user_warning_topic_ids = UserWarning.where(user_id:user.id).pluck(:topic_id)
        list = Topic.where(id: user_warning_topic_ids)
        create_list(:private_messages, {}, list)
      else
        super
      end
    end
  end

  class ::TopicQuery
    prepend OverrideTopicQuery
  end

  module OverridePostValidator
    def force_edit_last_validator(post)
      if post.topic && (
        SiteSetting.optimized_category_ignore_max_consecutive_replies.split("|").map(&:to_i).include?(post.topic.category_id) ||
        SiteSetting.optimized_tag_ignore_max_consecutive_replies.split("|").intersect?(post.topic.tags.pluck(:name))
      )
        return true
      else
        super
      end
    end
  end

  class ::PostValidator
    prepend OverridePostValidator
  end

  # 当用户删号时，保留用户的话题，并将话题移动到指定用户下
  register_user_destroyer_on_content_deletion_callback(
    Proc.new { |user|
      if SiteSetting.optimized_keep_topics_when_destroy_user
        target_user = User.find_by(username: SiteSetting.optimized_topics_move_to_when_destroy_user)
        user.topics.where(deleted_at:nil).each do |t|
          t.update(user_id: target_user.id)
          t.first_post.update(user_id: target_user.id)
        end
      end
    },
  )
end
