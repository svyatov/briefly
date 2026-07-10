# frozen_string_literal: true

require "active_support"
require "active_support/reloader"
require "active_support/environment_inquirer"
require "pathname"

# Stand-ins for the framework objects the Rails packs touch. The reloader is a real
# ActiveSupport::Reloader subclass, so `to_prepare` / `prepare!` semantics are genuinely exercised.
module RailsDouble
  Config = Struct.new(:x)
  Routes = Struct.new(:url_helpers)

  # Records what `render` was called with, so argument and block forwarding can be asserted.
  class Renderer
    attr_reader :calls

    def initialize = (@calls = [])

    def render(*args, **kwargs, &blk)
      @calls << [args, kwargs, blk&.call]
      "rendered"
    end
  end

  # Stands in for ApplicationController.
  class Controller
    attr_reader :helpers, :renderer

    def initialize
      @helpers = Object.new
      @renderer = Renderer.new
    end
  end

  # Records the statements `query` executes.
  class Connection
    attr_reader :queries

    def initialize = (@queries = [])

    def exec_query(sql)
      @queries << sql
      :result
    end
  end

  # Stands in for ApplicationRecord. `lease_connection` and `with_connection` hand out the same
  # connection, so a test can assert against it either way — reach it as `model.leased`.
  #
  # `connection` raises, mirroring a real `ActiveRecord.permanent_connection_checkout = :disallowed`.
  # Without that, the double answers the soft-deprecated method too, and every DB test stays green
  # while the pack reaches for an API that raises in production. The invariant needs a double that
  # can fail it.
  class Model
    attr_reader :leased, :transactions, :sanitized

    def initialize
      @leased = Connection.new
      @transactions = []
      @sanitized = []
    end

    def connection = raise(NoMethodError, "use lease_connection / with_connection")

    def lease_connection = @leased

    def with_connection = yield(@leased)

    def transaction(**opts, &blk)
      @transactions << opts
      blk.call
    end

    def sanitize_sql_array(array)
      @sanitized << array
      "sanitized(#{array.inspect})"
    end
  end

  # Stands in for Rails.application.
  class Application
    attr_reader :credentials, :routes, :reloader

    def initialize
      @credentials = Object.new
      @routes = Routes.new(Object.new)
      @reloader = Class.new(ActiveSupport::Reloader)
    end
  end

  # Stands in for the Rails module itself.
  class Framework
    attr_reader :configuration, :env, :root, :cache, :logger, :application

    def initialize(root:, env: "test")
      @configuration = Config.new(Object.new)
      @env = ActiveSupport::EnvironmentInquirer.new(env)
      @root = Pathname(root)
      @cache = Object.new
      @logger = Object.new
      @application = Application.new
    end
  end

  # Installs ::Rails, ::ApplicationController and ::ApplicationRecord for the duration of the block.
  #
  # @param root [String] value for Rails.root
  # @param env [String] value for Rails.env
  def self.with(root:, env: "test")
    Object.const_set(:Rails, Framework.new(root: root, env: env))
    Object.const_set(:ApplicationController, Controller.new)
    Object.const_set(:ApplicationRecord, Model.new)
    yield ::Rails, ::ApplicationController, ::ApplicationRecord
  ensure
    %i[Rails ApplicationController ApplicationRecord].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
  end
end
