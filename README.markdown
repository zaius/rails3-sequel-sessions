# rack-session-sequel

This module provides simple cookie based session management.
Session data is stored in database with [Sequel](http://sequel.rubyforge.org/).

## Usage

     DB = Sequel.sqlite
     DB.create_table :my_sessions do
       primary_key :id
       String :session_id
       text :data
     end
     use Rack::Session::Sequel, :dataset => DB[:my_sessions]
