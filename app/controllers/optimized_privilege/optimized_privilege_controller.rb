module OptimizedPrivilege
  class OptimizedPrivilegeController < ::ApplicationController
    requires_plugin OptimizedPrivilege

    before_action :ensure_logged_in

    def index
    end
  end
end
