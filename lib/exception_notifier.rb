require 'action_dispatch'
require 'exception_notifier/notifier'

class ExceptionNotifier
  def self.default_ignore_exceptions
    [].tap do |exceptions|
      exceptions << ActiveRecord::RecordNotFound if defined? ActiveRecord
      exceptions << AbstractController::ActionNotFound if defined? AbstractController
      exceptions << ActionController::RoutingError if defined? ActionController
    end
  end

  def initialize(app, options = {})
    @app, @options = app, options
    @options[:ignore_exceptions] ||= self.class.default_ignore_exceptions
  end

  def call(env)
    manually_raised = false

    status, headers, body = @app.call(env)

    if headers['X-Cascade'] == 'pass'
      manually_raised = true
      raise ActionController::RoutingError, "No route matches #{env['PATH_INFO'].inspect}"
    end

    [status, headers, body]
  rescue Exception => exception
    options = (env['exception_notifier.options'] ||= {})
    options.reverse_merge!(@options)

    should_ignore   = Array.wrap(options[:ignore_exceptions]).include?(exception.class)
    should_ignore ||= begin
      controller = env['action_controller.instance'] and
      controller.respond_to?(:ignore_notification_of_exception?) and
      controller.ignore_notification_of_exception?(::Rack::Request.new(env), exception) == true
    end

    unless should_ignore
      Notifier.exception_notification(env, exception).deliver
      env['exception_notifier.delivered'] = true
    end

    raise exception unless manually_raised
    return [status, headers, body]
  end
end
