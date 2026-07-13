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

  # Stands in for Rails.application. `config_for` records the name and options it was called with, so
  # forwarding can be asserted, and returns a recognizable value.
  class Application
    attr_reader :credentials, :routes, :reloader, :config_for_calls

    def initialize
      @credentials = Object.new
      @routes = Routes.new(Object.new)
      @reloader = Class.new(ActiveSupport::Reloader)
      @config_for_calls = []
    end

    def config_for(name, **opts)
      @config_for_calls << [name, opts]
      { config_for: name }
    end
  end

  # Stands in for the Rails module itself. `error` stands in for the framework's handled-error reporter.
  class Framework
    attr_reader :configuration, :env, :root, :cache, :logger, :application, :error

    def initialize(root:, env: "test")
      @configuration = Config.new(Object.new)
      @env = ActiveSupport::EnvironmentInquirer.new(env)
      @root = Pathname(root)
      @cache = Object.new
      @logger = Object.new
      @application = Application.new
      @error = Object.new
    end
  end

  # Installs ::Rails, ::ApplicationController and ::ApplicationRecord for the duration of the block.
  # The DB pack is tested against real Active Record (see support/active_record.rb); here
  # ApplicationRecord only needs to exist as a constant so the umbrella can mount its `db` namespace.
  #
  # @param root [String] value for Rails.root
  # @param env [String] value for Rails.env
  def self.with(root:, env: "test")
    Object.const_set(:Rails, Framework.new(root: root, env: env))
    Object.const_set(:ApplicationController, Controller.new)
    Object.const_set(:ApplicationRecord, Object.new)
    yield ::Rails, ::ApplicationController, ::ApplicationRecord
  ensure
    %i[Rails ApplicationController ApplicationRecord].each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name, false)
    end
  end
end
