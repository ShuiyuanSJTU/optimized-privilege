require_dependency "optimized_privilege_constraint"

OptimizedPrivilege::Engine.routes.draw do
  get "/" => "optimized_privilege#index", constraints: OptimizedPrivilegeConstraint.new
  get "/actions" => "actions#index", constraints: OptimizedPrivilegeConstraint.new
  get "/actions/:id" => "actions#show", constraints: OptimizedPrivilegeConstraint.new
end
