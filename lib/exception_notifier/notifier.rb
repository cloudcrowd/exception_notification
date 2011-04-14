require 'action_mailer'
require 'pp'

class ExceptionNotifier
  class Notifier < ActionMailer::Base
    self.mailer_name = 'exception_notifier'

    # Allow application templates to override default templates
    self.append_view_path "#{Rails.root}/app/views" if defined? Rails
    self.append_view_path "#{File.dirname(__FILE__)}/views"

    class << self
      def default_sender_address
        %("Exception Notifier" <exception.notifier@default.com>)
      end

      def default_exception_recipients
        []
      end

      def default_email_prefix
        "[ERROR] "
      end

      def default_sections
        %w(request session environment backtrace)
      end

      def default_options
        { :sender_address => default_sender_address,
          :exception_recipients => default_exception_recipients,
          :email_prefix => default_email_prefix,
          :sections => default_sections }
      end
    end

    class MissingController
      def method_missing(*args, &block)
      end
    end

    def exception_notification(env, exception)
      @env        = env
      @exception  = exception
      @options    = (env['exception_notifier.options'] || {}).reverse_merge(self.class.default_options)
      @kontroller = env['action_controller.instance'] || MissingController.new
      @request    = ActionDispatch::Request.new(env) unless env['non_web_app']
      @backtrace  = clean_backtrace(exception) if exception
      @sections   = @options[:sections]
      data        = env['exception_notifier.exception_data'] || {}

      data.each do |name, value|
        instance_variable_set("@#{name}", value)
      end

      subject = render("#{mailer_name}/subject").chomp

      # FIXME, this is a hack to use Non-SSL connection to deliver exception
      # email, need to review whether this is secure.
      if ActionMailer::Base.delivery_method == :smtp
        ActionMailer::Base.smtp_settings.merge!({:enable_starttls_auto => false})
      end

      mail(:to => @options[:exception_recipients], :from => @options[:sender_address], :subject => subject) do |format|
        format.text { render "#{mailer_name}/exception_notification" }
      end
    end

    private

      def clean_backtrace(exception)
        Object.const_defined?(:Rails) && Rails.respond_to?(:backtrace_cleaner) ?
          Rails.backtrace_cleaner.send(:filter, exception.backtrace) :
          exception.backtrace
      end

      helper_method :inspect_object

      def inspect_object(object)
        if object.kind_of?(Hash) || object.kind_of?(Array)
          return object.inspect
        end

        # make no assumption that we are running inside rails
        if Object.const_defined?(:ActionController) && ActionController.const_defined?(:Base)
          if object.kind_of?(ActionController::Base)
            return "#{object.controller_name}##{object.action_name}"
          end
        end
        return object.to_s
      end

  end
end
