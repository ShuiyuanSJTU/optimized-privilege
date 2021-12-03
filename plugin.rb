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
    if SiteSetting.optimized_privilege_enabled
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
                    return true if is_my_own?(topic)
                    false
                else super
                end
            end
            alias :can_open_topic? :can_close_topic?
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
        
        class ::UsersController
            before_action :check_change_username_limit, only: [:username]
            after_action :add_change_username_limit, only: [:username]
            def check_change_username_limit
                if SiteSetting.optimized_change_username && !current_user&.staff?
                    params.require(:username)
                    old = ::PluginStore.get("change-username", params[:username].downcase)
                    if old
                        time = Time.parse(old) + SiteSetting.optimized_username_change_period * 86400
                        if Time.now < time
                            return render json: { success: false, message: "正处于更名间隔期，请于#{time.strftime("%Y-%m-%d %H:%M:%S %Z")}之后再尝试！" }, status: 403
                        end
                    end
                end
            end

            def add_change_username_limit
                if SiteSetting.optimized_change_username
                    ::PluginStore.remove("change-username", params[:username].downcase)
                    ::PluginStore.set("change-username", params[:new_username].downcase, Time.now)
                end
            end
        end
        class ::Guardian
            prepend OverridingTopicGuardian
            prepend OverrideUserGuardian
        end
    end
    
end
