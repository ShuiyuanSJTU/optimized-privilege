require 'rails_helper'

describe optimized-privilege::ActionsController do
  before do
    Jobs.run_immediately!
  end

  it 'can list' do
    sign_in(Fabricate(:user))
    get "/optimized-privilege/list.json"
    expect(response.status).to eq(200)
  end
end
