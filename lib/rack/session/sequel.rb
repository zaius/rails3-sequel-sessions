# coding: utf-8

require "rack/session/abstract/id"
require "sequel"

module Rack

  module Session

    # Example:
    #     DB = Sequel.sqlite
    #     DB.create_table :my_sessions do
    #       primary_key :id
    #       String :session_id
    #       text :data
    #     end
    #     use Rack::Session::Sequel, :dataset => DB[:my_sessions]
    #
    #  You can change a table name as you like,
    #  but cannot change column names.
    class Sequel < Abstract::ID
      attr_reader :dataset, :session_id_column, :data_column
      DEFAULT_OPTIONS = Abstract::ID::DEFAULT_OPTIONS.merge \
        :dataset => nil

      def initialize(app, options = {})
        super
        @dataset = @default_options[:dataset]
        raise 'No dataset instance' unless @dataset
      end

      def generate_sid
        loop do
          sid = super
          break sid unless @dataset[:session_id => sid]
        end
      end

      def get_session(env, sid)
        session = unpack(@dataset[:session_id => sid][:data]) if sid
        unless sid and session 
          env['rack.errors'].puts("Session '#{sid.inspect}' not found, initializing...") if $VERBOSE and not sid.nil?
          session = {}
          sid = generate_sid
          @dataset.insert(:session_id => sid, :data => pack(session))
        end
        session.instance_variable_set('@old', {}.merge(session))
        return [sid, session]
      end

      def set_session(env, session_id, new_session, options)
        session = unpack(@dataset[:session_id => session_id][:data])
        if options[:renew]
          @dataset.filter(:session_id => session_id).delete
          session_id = generate_sid
          @dataset.insert(:session_id => session_id, :data => pack({}))
        end
        old_session = new_session.instance_variable_get('@old') || {}
        session = merge_sessions session_id, old_session, new_session, session
        @dataset.filter(:session_id => session_id).update(:data => pack(session))
        return session_id
      end

      private

      def pack(session)
        [Marshal.dump(session)].pack("m*")
      end

      def unpack(packed)
        return nil unless packed
        Marshal.load(packed.unpack("m*").first)
      end

      def merge_sessions sid, old, new, cur=nil
        cur ||= {}
        unless Hash === old and Hash === new 
          warn 'Bad old or new sessions provided.'
          return cur
        end

        delete = old.keys - new.keys
        warn "//@#{sid}: dropping #{delete*','}" if $DEBUG and not delete.empty?
        delete.each{|k| cur.delete k }

        update = new.keys.select{|k| new[k] != old[k] }
        warn "//@#{sid}: updating #{update*','}" if $DEBUG and not update.empty?
        update.each{|k| cur[k] = new[k] }

        cur
      end

    end

  end

end
