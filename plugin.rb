# frozen_string_literal: true

# name: optimized-privilege
# about: 
# version: 0.1
# authors: dujiajun
# url: https://github.com/dujiajun/optimized-privilege.git

register_asset 'stylesheets/common/optimized-privilege.scss'
register_asset 'stylesheets/desktop/optimized-privilege.scss', :desktop
register_asset 'stylesheets/mobile/optimized-privilege.scss', :mobile

enabled_site_setting :optimized_privilege_enabled

PLUGIN_NAME ||= 'OptimizedPrivilege'

load File.expand_path('lib/optimized-privilege/engine.rb', __dir__)

after_initialize do
  # https://github.com/discourse/discourse/blob/master/lib/plugin/instance.rb

  class ::TopicViewDetailsSerializer
    module OverridingTopicViewDetailsSerializer
      def include_can_close_topic? 
        scope.can_close_topic?(object.topic)
      end
      alias :include_can_split_merge_topic? :include_can_close_topic?
      alias :include_can_archive_topic? :include_can_close_topic?
    end
    prepend OverridingTopicViewDetailsSerializer
  end
  
  class ::Guardian
    module OverridingGuardian

      def can_delete_post?(post)
        return true if super(post)
        # You can delete your own posts
        if is_my_own?(post)
          return false if (SiteSetting.max_post_deletions_per_minute < 1 || SiteSetting.max_post_deletions_per_day < 1)
          return true if !post.user_deleted?
        end
    
        false
      end
     
      def can_close_topic?(topic)
        return true if super(topic)
        return true if is_my_own?(topic)
        false
      end

      def can_toggle_topic_visibility?(topic)
        return true if super(topic)
        return true if is_my_own?(topic)
        false
      end

      def can_move_posts?(topic)
        return true if super(topic)
        return true if is_my_own?(topic)
        false
      end

      alias :can_archive_topic? :can_close_topic?
      alias :can_split_merge_topic? :can_close_topic?
      alias :can_open_topic? :can_close_topic?
    end
    
    prepend OverridingGuardian

  end
  


end
