class OptimizedPrivilegeConstraint
  def matches?(request)
    SiteSetting.optimized_privilege_enabled
  end
end
