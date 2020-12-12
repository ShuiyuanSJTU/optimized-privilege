module OptimizedPrivilege
  class Engine < ::Rails::Engine
    engine_name "OptimizedPrivilege".freeze
    isolate_namespace OptimizedPrivilege

    config.after_initialize do
      Discourse::Application.routes.append do
        mount ::OptimizedPrivilege::Engine, at: "/optimized-privilege"
      end
    end
  end
end
