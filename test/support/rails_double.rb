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

  # Installs ::Rails and ::ApplicationController for the duration of the block.
  #
  # @param root [String] value for Rails.root
  # @param env [String] value for Rails.env
  def self.with(root:, env: "test")
    Object.const_set(:Rails, Framework.new(root: root, env: env))
    Object.const_set(:ApplicationController, Controller.new)
    yield ::Rails, ::ApplicationController
  ensure
    Object.send(:remove_const, :Rails) if Object.const_defined?(:Rails, false)
    Object.send(:remove_const, :ApplicationController) if Object.const_defined?(:ApplicationController, false)
  end
end
