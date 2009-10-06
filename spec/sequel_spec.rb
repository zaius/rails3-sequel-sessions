# coding: utf-8

require "#{File.dirname(__FILE__)}/../lib/rack/session/sequel"
require "rack/mock"
require "rack/response"

class Spec::Example::ExampleGroup
  def execute(*args, &block)
    DB.transaction{super(*args, &block); raise Sequel::Error::Rollback}
  end
end

describe Rack::Session::Sequel do
  session_key = Rack::Session::Sequel::DEFAULT_OPTIONS[:key]
  session_match = /#{session_key}=[0-9a-fA-F]+;/
  incrementor = lambda do |env|
    env["rack.session"]["counter"] ||= 0
    env["rack.session"]["counter"] += 1
    Rack::Response.new(env["rack.session"].inspect).to_a
  end
  renew_session = proc do |env|
    env["rack.session.options"][:renew] = true
    incrementor.call(env)
  end
  defer_session = proc do |env|
    env["rack.session.options"][:defer] = true
    incrementor.call(env)
  end

  before :all do
    DB = Sequel.sqlite
    DB.create_table :rack_sessions do
      primary_key :id
      String :session_id
      text :data
    end
    @dataset = DB[:rack_sessions]
  end

  it "should create a new cookie" do
    sequel = Rack::Session::Sequel.new(incrementor, :dataset => @dataset)
    res = Rack::MockRequest.new(sequel).get("/")
    res["Set-Cookie"].should =~ session_match
    res.body.should == '{"counter"=>1}'
  end

  it "should determine session from a cookie" do
    sequel = Rack::Session::Sequel.new(incrementor, :dataset => @dataset)
    req = Rack::MockRequest.new(sequel)
    cookie = req.get("/")["Set-Cookie"]
    req.get("/", "HTTP_COOKIE" => cookie).
      body.should == '{"counter"=>2}'
    req.get("/", "HTTP_COOKIE" => cookie).
      body.should == '{"counter"=>3}'
  end

  it "should survive nonexistant cookies" do
    sequel = Rack::Session::Sequel.new(incrementor, :dataset => @dataset)
    res = Rack::MockRequest.new(sequel).
      get("/", "HTTP_COOKIE" => "#{session_key}=qwerty")
    res.body.should == '{"counter"=>1}'
  end

  it "should provide new session id with :renew option" do
    sequel = Rack::Session::Sequel.new(incrementor, :dataset => @dataset)
    req = Rack::MockRequest.new(sequel)
    renew = Rack::Utils::Context.new(sequel, renew_session)
    rreq = Rack::MockRequest.new(renew)

    res0 = req.get("/")
    session = (cookie = res0["Set-Cookie"])[session_match]
    res0.body.should == '{"counter"=>1}'
    sequel.dataset.count.should equal(1)

    res1 = req.get("/", "HTTP_COOKIE" => cookie)
    res1["Set-Cookie"][session_match].should == session
    res1.body.should == '{"counter"=>2}'
    sequel.dataset.count.should equal(1)

    res2 = rreq.get("/", "HTTP_COOKIE" => cookie)
    new_cookie = res2["Set-Cookie"]
    new_session = new_cookie[session_match]
    new_session.should_not == session
    res2.body.should == '{"counter"=>3}'
    sequel.dataset.count.should equal(1)

    res3 = req.get("/", "HTTP_COOKIE" => new_cookie)
    res3["Set-Cookie"][session_match].should == new_session
    res3.body.should == '{"counter"=>4}'
    sequel.dataset.count.should equal(1)
  end
 
  it "should omit cookie with :defer option" do
    sequel = Rack::Session::Sequel.new(incrementor, :dataset => @dataset)
    req = Rack::MockRequest.new(sequel)
    defer = Rack::Utils::Context.new(sequel, defer_session)
    dreq = Rack::MockRequest.new(defer)

    res0 = req.get("/")
    session = (cookie = res0["Set-Cookie"])[session_match]
    res0.body.should == '{"counter"=>1}'
    sequel.dataset.count.should equal(1)

    res1 = req.get("/", "HTTP_COOKIE" => cookie)
    res1["Set-Cookie"][session_match].should == session
    res1.body.should == '{"counter"=>2}'
    sequel.dataset.count.should equal(1)

    res2 = dreq.get("/", "HTTP_COOKIE" => cookie)
    res2["Set-Cookie"].should be_nil
    res2.body.should == '{"counter"=>3}'
    sequel.dataset.count.should equal(1)

    res3 = req.get("/", "HTTP_COOKIE" => cookie)
    res3["Set-Cookie"][session_match].should == session
    res3.body.should == '{"counter"=>4}'
    sequel.dataset.count.should equal(1)
  end
end

