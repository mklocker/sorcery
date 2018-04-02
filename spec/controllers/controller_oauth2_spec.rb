require 'spec_helper'

# require 'shared_examples/controller_oauth2_shared_examples'

describe SorceryController, :active_record => true do
  before(:all) do
    if SORCERY_ORM == :active_record
      ActiveRecord::Migrator.migrate("#{Rails.root}/db/migrate/external")
      User.reset_column_information
    end

    sorcery_reload!([:external])
    set_external_property
  end

  after(:all) do
    if SORCERY_ORM == :active_record
      ActiveRecord::Migrator.rollback("#{Rails.root}/db/migrate/external")
    end
  end

  describe 'using create_from' do
    before(:each) do
      stub_all_oauth2_requests!
    end

    it 'creates a new user' do
      sorcery_model_property_set(:authentications_class, Authentication)
      sorcery_controller_external_property_set(:facebook, :user_info_mapping, { username: 'name' })

      expect(User).to receive(:create_from_provider).with('facebook', '123', {username: 'Noam Ben Ari'})
      get :test_create_from_provider, provider: 'facebook'
    end

    it 'supports nested attributes' do
      sorcery_model_property_set(:authentications_class, Authentication)
      sorcery_controller_external_property_set(:facebook, :user_info_mapping, { username: 'hometown/name' })
      expect(User).to receive(:create_from_provider).with('facebook', '123', {username: 'Haifa, Israel'})

      get :test_create_from_provider, provider: 'facebook'
    end

    it 'does not crash on missing nested attributes' do
      sorcery_model_property_set(:authentications_class, Authentication)
      sorcery_controller_external_property_set(:facebook, :user_info_mapping, { username: 'name', created_at: 'does/not/exist' })

      expect(User).to receive(:create_from_provider).with('facebook', '123', {username: 'Noam Ben Ari'})

      get :test_create_from_provider, provider: 'facebook'
    end

    describe 'with a block' do
      it 'does not create user' do
        sorcery_model_property_set(:authentications_class, Authentication)
        sorcery_controller_external_property_set(:facebook, :user_info_mapping, { username: 'name' })

        u = double('user')
        expect(User).to receive(:create_from_provider).with('facebook', '123', {username: 'Noam Ben Ari'}).and_return(u).and_yield(u)
        # test_create_from_provider_with_block in controller will check for uniqueness of username
        get :test_create_from_provider_with_block, provider: 'facebook'
      end
    end
  end

  # ----------------- OAuth -----------------------
  context "with OAuth features" do

    let(:user) { double('user', id: 42) }

    before(:each) do
      stub_all_oauth2_requests!
      stub_all_openid_connect_requests!
    end

    after(:each) do
      User.sorcery_adapter.delete_all
      Authentication.sorcery_adapter.delete_all
    end

    context "when callback_url begin with /" do
      before do
        sorcery_controller_external_property_set(:facebook, :callback_url, "/oauth/twitter/callback")
      end
      it "login_at redirects correctly" do
        get :login_at_test_facebook
        expect(response).to be_a_redirect
        expect(response).to redirect_to("https://www.facebook.com/dialog/oauth?client_id=#{::Sorcery::Controller::Config.facebook.key}&display=page&redirect_uri=http%3A%2F%2Ftest.host%2Foauth%2Ftwitter%2Fcallback&response_type=code&scope=email&state")
      end

      it "logins with state" do
        get :login_at_test_with_state
        expect(response).to be_a_redirect
        expect(response).to redirect_to("https://www.facebook.com/dialog/oauth?client_id=#{::Sorcery::Controller::Config.facebook.key}&display=page&redirect_uri=http%3A%2F%2Ftest.host%2Foauth%2Ftwitter%2Fcallback&response_type=code&scope=email&state=bla")
      end

      it "logins with Graph API version" do
        sorcery_controller_external_property_set(:facebook, :api_version, "v2.2")
        get :login_at_test_with_state
        expect(response).to be_a_redirect
        expect(response).to redirect_to("https://www.facebook.com/v2.2/dialog/oauth?client_id=#{::Sorcery::Controller::Config.facebook.key}&display=page&redirect_uri=http%3A%2F%2Ftest.host%2Foauth%2Ftwitter%2Fcallback&response_type=code&scope=email&state=bla")
      end

      it "logins without state after login with state" do
        get :login_at_test_with_state
        expect(response).to redirect_to("https://www.facebook.com/v2.2/dialog/oauth?client_id=#{::Sorcery::Controller::Config.facebook.key}&display=page&redirect_uri=http%3A%2F%2Ftest.host%2Foauth%2Ftwitter%2Fcallback&response_type=code&scope=email&state=bla")

        get :login_at_test_facebook
        expect(response).to redirect_to("https://www.facebook.com/v2.2/dialog/oauth?client_id=#{::Sorcery::Controller::Config.facebook.key}&display=page&redirect_uri=http%3A%2F%2Ftest.host%2Foauth%2Ftwitter%2Fcallback&response_type=code&scope=email&state")
      end

      after do
        sorcery_controller_external_property_set(:facebook, :callback_url, "http://blabla.com")
      end
    end

    context "when callback_url begin with http://" do
      it "login_at redirects correctly" do
        create_new_user
        get :login_at_test_facebook
        expect(response).to be_a_redirect
        expect(response).to redirect_to("https://www.facebook.com/v2.2/dialog/oauth?client_id=#{::Sorcery::Controller::Config.facebook.key}&display=page&redirect_uri=http%3A%2F%2Ftest.host%2Foauth%2Ftwitter%2Fcallback&response_type=code&scope=email&state")
      end
    end

    it "'login_from' logins if user exists" do
      # dirty hack for rails 4
      allow(subject).to receive(:register_last_activity_time_to_db)

      sorcery_model_property_set(:authentications_class, Authentication)
      expect(User).to receive(:load_from_provider).with(:facebook, '123').and_return(user)
      get :test_login_from_facebook

      expect(flash[:notice]).to eq "Success!"
    end

    it "'login_from' fails if user doesn't exist" do
      sorcery_model_property_set(:authentications_class, Authentication)
      expect(User).to receive(:load_from_provider).with(:facebook, '123').and_return(nil)
      get :test_login_from_facebook

      expect(flash[:alert]).to eq "Failed!"
    end

    it "on successful login_from the user is redirected to the url he originally wanted" do
      # dirty hack for rails 4
      allow(subject).to receive(:register_last_activity_time_to_db)

      sorcery_model_property_set(:authentications_class, Authentication)
      expect(User).to receive(:load_from_provider).with(:facebook, '123').and_return(user)
      get :test_return_to_with_external_facebook, {}, :return_to_url => "fuu"

      expect(response).to redirect_to("fuu")
      expect(flash[:notice]).to eq "Success!"
    end

    [:github, :google, :liveid, :vk, :salesforce, :paypal, :openid_connect].each do |provider|

      describe "with #{provider}" do

        it "login_at redirects correctly" do
          get :"login_at_test_#{provider}"

          expect(response).to be_a_redirect
          expect(response).to redirect_to(provider_url provider)
        end

        it "'login_from' logins if user exists" do
          # dirty hack for rails 4
          allow(subject).to receive(:register_last_activity_time_to_db)

          sorcery_model_property_set(:authentications_class, Authentication)
          expect(User).to receive(:load_from_provider).with(provider, '123').and_return(user)
          get :"test_login_from_#{provider}"

          expect(flash[:notice]).to eq "Success!"
        end

        it "'login_from' fails if user doesn't exist" do
          sorcery_model_property_set(:authentications_class, Authentication)
          expect(User).to receive(:load_from_provider).with(provider, '123').and_return(nil)
          get :"test_login_from_#{provider}"

          expect(flash[:alert]).to eq "Failed!"
        end

        it "on successful login_from the user is redirected to the url he originally wanted (#{provider})" do
          # dirty hack for rails 4
          allow(subject).to receive(:register_last_activity_time_to_db)

          sorcery_model_property_set(:authentications_class, Authentication)
          expect(User).to receive(:load_from_provider).with(provider, '123').and_return(user)
          get :"test_return_to_with_external_#{provider}", {}, :return_to_url => "fuu"

          expect(response).to redirect_to "fuu"
          expect(flash[:notice]).to eq "Success!"
        end
      end
    end

  end

  describe "OAuth with User Activation features" do
    before(:all) do
      if SORCERY_ORM == :active_record
        ActiveRecord::Migrator.migrate("#{Rails.root}/db/migrate/activation")
      end

      sorcery_reload!([:user_activation,:external], :user_activation_mailer => ::SorceryMailer)
      sorcery_controller_property_set(:external_providers, [:facebook, :github, :google, :liveid, :vk, :salesforce, :paypal])

      sorcery_controller_external_property_set(:facebook, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:facebook, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:facebook, :callback_url, "http://blabla.com")
      sorcery_controller_external_property_set(:github, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:github, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:github, :callback_url, "http://blabla.com")
      sorcery_controller_external_property_set(:google, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:google, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:google, :callback_url, "http://blabla.com")
      sorcery_controller_external_property_set(:liveid, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:liveid, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:liveid, :callback_url, "http://blabla.com")
      sorcery_controller_external_property_set(:vk, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:vk, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:vk, :callback_url, "http://blabla.com")
      sorcery_controller_external_property_set(:salesforce, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:salesforce, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:salesforce, :callback_url, "http://blabla.com")
      sorcery_controller_external_property_set(:paypal, :key, "eYVNBjBDi33aa9GkA3w")
      sorcery_controller_external_property_set(:paypal, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
      sorcery_controller_external_property_set(:paypal, :callback_url, "http://blabla.com")
    end

    after(:all) do
      if SORCERY_ORM == :active_record
        ActiveRecord::Migrator.rollback("#{Rails.root}/db/migrate/activation")
      end
    end

    after(:each) do
      User.sorcery_adapter.delete_all
    end

    it "does not send activation email to external users" do
      old_size = ActionMailer::Base.deliveries.size
      create_new_external_user(:facebook)

      expect(ActionMailer::Base.deliveries.size).to eq old_size
    end

    it "does not send external users an activation success email" do
      sorcery_model_property_set(:activation_success_email_method_name, nil)
      create_new_external_user(:facebook)
      old_size = ActionMailer::Base.deliveries.size
      @user.activate!

      expect(ActionMailer::Base.deliveries.size).to eq old_size
    end

    [:github, :google, :liveid, :vk, :salesforce, :paypal].each do |provider|
      it "does not send activation email to external users (#{provider})" do
        old_size = ActionMailer::Base.deliveries.size
        create_new_external_user provider
        expect(ActionMailer::Base.deliveries.size).to eq old_size
      end

      it "does not send external users an activation success email (#{provider})" do
        sorcery_model_property_set(:activation_success_email_method_name, nil)
        create_new_external_user provider
        old_size = ActionMailer::Base.deliveries.size
        @user.activate!
      end
    end
  end

  describe "OAuth with user activation features"  do

    let(:user) { double('user', id: 42) }

    before(:all) do
      sorcery_reload!([:activity_logging, :external])
    end

    after(:all) do
      if SORCERY_ORM == :active_record
        ActiveRecord::Migrator.rollback("#{Rails.root}/db/migrate/external")
        ActiveRecord::Migrator.rollback("#{Rails.root}/db/migrate/activity_logging")
      end
    end

    %w(facebook github google liveid vk salesforce).each do |provider|
      context "when #{provider}" do
        before(:each) do
          sorcery_controller_property_set(:register_login_time, true)
          sorcery_controller_property_set(:register_logout_time, false)
          sorcery_controller_property_set(:register_last_activity_time, false)
          sorcery_controller_property_set(:register_last_ip_address, false)
          stub_all_oauth2_requests!
          sorcery_model_property_set(:authentications_class, Authentication)
        end

        it "registers login time" do
          now = Time.now.in_time_zone
          Timecop.freeze(now)
          expect(User).to receive(:load_from_provider).and_return(user)
          expect(user).to receive(:set_last_login_at).with(be_within(0.1).of(now))
          get "test_login_from_#{provider}".to_sym
          Timecop.return
        end

        it "does not register login time if configured so" do
          sorcery_controller_property_set(:register_login_time, false)
          now = Time.now.in_time_zone
          Timecop.freeze(now)
          expect(User).to receive(:load_from_provider).and_return(user)
          expect(user).to receive(:set_last_login_at).never
          get "test_login_from_#{provider}".to_sym

        end
      end
    end
  end

  describe "OAuth with session timeout features" do
    before(:all) do
      sorcery_reload!([:session_timeout, :external])
    end

    let(:user) { double('user', id: 42) }

    %w(facebook github google liveid vk salesforce).each do |provider|
      context "when #{provider}" do
        before(:each) do
          sorcery_model_property_set(:authentications_class, Authentication)
          sorcery_controller_property_set(:session_timeout,0.5)
          stub_all_oauth2_requests!
        end

        after(:each) do
          Timecop.return
        end

        it "does not reset session before session timeout" do
          expect(User).to receive(:load_from_provider).with(provider.to_sym, '123').and_return(user)
          get "test_login_from_#{provider}".to_sym

          expect(session[:user_id]).not_to be_nil
          expect(flash[:notice]).to eq "Success!"
        end

        it "resets session after session timeout" do
          expect(User).to receive(:load_from_provider).with(provider.to_sym, '123').and_return(user)
          get "test_login_from_#{provider}".to_sym
          expect(session[:user_id]).to eq "42"
          Timecop.travel(Time.now.in_time_zone+0.6)
          get :test_should_be_logged_in

          expect(session[:user_id]).to be_nil
          expect(response).to be_a_redirect
        end
      end
    end
  end

  def stub_all_oauth2_requests!
    access_token    = double(OAuth2::AccessToken)
    allow(access_token).to receive(:token_param=)
    response        = double(OAuth2::Response)
    allow(response).to receive(:body) { {
      "id"=>"123",
      "user_id"=>"123", # Needed for Salesforce
      "name"=>"Noam Ben Ari",
      "first_name"=>"Noam",
      "last_name"=>"Ben Ari",
      "link"=>"http://www.facebook.com/nbenari1",
      "hometown"=>{"id"=>"110619208966868", "name"=>"Haifa, Israel"},
      "location"=>{"id"=>"106906559341067", "name"=>"Pardes Hanah, Hefa, Israel"},
      "bio"=>"I'm a new daddy, and enjoying it!",
      "gender"=>"male",
      "email"=>"nbenari@gmail.com",
      "timezone"=>2,
      "locale"=>"en_US",
      "languages"=>[{"id"=>"108405449189952", "name"=>"Hebrew"}, {"id"=>"106059522759137", "name"=>"English"}, {"id"=>"112624162082677", "name"=>"Russian"}],
      "verified"=>true,
      "updated_time"=>"2011-02-16T20:59:38+0000",
      # response for VK auth
      "response"=>[
          {
            "uid"=>"123",
            "first_name"=>"Noam",
            "last_name"=>"Ben Ari"
            }
        ]}.to_json }
    allow(access_token).to receive(:get) { response }
    allow(access_token).to receive(:token) { "187041a618229fdaf16613e96e1caabc1e86e46bbfad228de41520e63fe45873684c365a14417289599f3" }
    # access_token params for VK auth
    allow(access_token).to receive(:params) { { "user_id"=>"100500", "email"=>"nbenari@gmail.com" } }
    allow_any_instance_of(OAuth2::Strategy::AuthCode).to receive(:get_token) { access_token }
  end

  def stub_all_openid_connect_requests!
    
    # Id token
    id_token = double(OpenIDConnect::ResponseObject::IdToken)
    allow(id_token).to receive(:sub).and_return('123')    
    allow(id_token).to receive(:raw_attributes) {
       {
         iss: 'accounts.google.com',
         aud: '999220227102-jr200rnb4inkmln67vvo56kf86i1bnch.apps.googleusercontent.com',
         sub: '123',
         azp: '999220227102-jr200rnb4inkmln67vvo56kf86i1bnch.apps.googleusercontent.com',
         iat: 1443571350,
         exp: 1443574950
       }
    }
    allow(OpenIDConnect::ResponseObject::IdToken).to receive(:decode).with(any_args).and_return(id_token)
    
    # Access token
    access_token = double(OpenIDConnect::AccessToken)
    allow(access_token).to receive(:access_token) {
      'access_token_key'
    }    
    allow(access_token).to receive(:id_token) {
      'id_token'
    }    

    allow_any_instance_of(Sorcery::Providers::Openid_connect).to receive(:get_public_keys) { nil }
    allow_any_instance_of(OpenIDConnect::Client).to receive(:access_token!).and_return(access_token)      
    allow_any_instance_of(OpenIDConnect::Client).to receive(:authorization_code=) { nil }    
  end

  def set_external_property
    sorcery_controller_property_set(:external_providers, [:facebook, :github, :google, :liveid, :vk, :salesforce, :paypal, :openid_connect])
    sorcery_controller_external_property_set(:facebook, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:facebook, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:facebook, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:github, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:github, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:github, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:google, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:google, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:google, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:liveid, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:liveid, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:liveid, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:vk, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:vk, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:vk, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:salesforce, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:salesforce, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:salesforce, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:openid_connect, :key, "999220227102-1us4vq0k6t0orb3hoqepftd5u8ef8vec.apps.googleusercontent.com")
    sorcery_controller_external_property_set(:openid_connect, :secret, "Y0qFZfsjzTQbQSSc2dPVMTbb")
    sorcery_controller_external_property_set(:openid_connect, :callback_url, "http://blabla.com")
    sorcery_controller_external_property_set(:openid_connect, :auth_path, "https://accounts.google.com/o/oauth2/auth")
    sorcery_controller_external_property_set(:openid_connect, :token_url, "https://accounts.google.com/o/oauth2/token")
    sorcery_controller_external_property_set(:paypal, :key, "eYVNBjBDi33aa9GkA3w")
    sorcery_controller_external_property_set(:paypal, :secret, "XpbeSdCoaKSmQGSeokz5qcUATClRW5u08QWNfv71N8")
    sorcery_controller_external_property_set(:paypal, :callback_url, "http://blabla.com")
  end

  def provider_url(provider)
    {
      openid_connect: "https://accounts.google.com/o/oauth2/auth?client_id=#{::Sorcery::Controller::Config.openid_connect.key}&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope=openid",
      github: "https://github.com/login/oauth/authorize?client_id=#{::Sorcery::Controller::Config.github.key}&display&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope&state",
      paypal: "https://www.paypal.com/webapps/auth/protocol/openidconnect/v1/authorize?client_id=#{::Sorcery::Controller::Config.paypal.key}&display&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope=openid+email&state",
      google: "https://accounts.google.com/o/oauth2/auth?client_id=#{::Sorcery::Controller::Config.google.key}&display&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.email+https%3A%2F%2Fwww.googleapis.com%2Fauth%2Fuserinfo.profile&state",
      liveid: "https://oauth.live.com/authorize?client_id=#{::Sorcery::Controller::Config.liveid.key}&display&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope=wl.basic+wl.emails+wl.offline_access&state",
      vk: "https://oauth.vk.com/authorize?client_id=#{::Sorcery::Controller::Config.vk.key}&display&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope=#{::Sorcery::Controller::Config.vk.scope}&state",
      salesforce: "https://login.salesforce.com/services/oauth2/authorize?client_id=#{::Sorcery::Controller::Config.salesforce.key}&display&redirect_uri=http%3A%2F%2Fblabla.com&response_type=code&scope#{'=' + ::Sorcery::Controller::Config.salesforce.scope unless ::Sorcery::Controller::Config.salesforce.scope.nil?}&state"
    }[provider]
  end
end
