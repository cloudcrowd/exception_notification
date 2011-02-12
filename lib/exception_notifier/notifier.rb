require 'action_mailer'
require 'pp'

class ExceptionNotifier
  class Notifier < ActionMailer::Base
    self.mailer_name = 'exception_notifier'
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
      @request    = ActionDispatch::Request.new(env)
      @backtrace  = clean_backtrace(exception)
      @sections   = @options[:sections]
      data        = env['exception_notifier.exception_data'] || {}

      data.each do |name, value|
        instance_variable_set("@#{name}", value)
      end

      subject = render("#{mailer_name}/subject")

      # FIXME, :sendmail mail delivery method does not seem to work
      if @options[:method] && @options[:method] != :smtp
        ActionMailer::Base.delivery_method = @options[:method]
      end

      # FIXME make sendmail work
      if ActionMailer::Base.delivery_method == :sendmail
        $LOG.warn {"sendmail exception notification method not working yet"} if $LOG
      end

      # FIXME, this is a hack to use Non-SSL connection to deliver exception email, need to review whether this is secure
      if ActionMailer::Base.delivery_method == :smtp
        ActionMailer::Base.smtp_settings.merge!({:enable_starttls_auto => false})
      end

      mail(:to => @options[:exception_recipients], :from => @options[:sender_address], :subject => subject) do |format|
        format.text { render "#{mailer_name}/exception_notification" }
      end
    end

    private

      def clean_backtrace(exception)
        Rails.respond_to?(:backtrace_cleaner) ?
          Rails.backtrace_cleaner.send(:filter, exception.backtrace) :
          exception.backtrace
      end

      helper_method :inspect_object

      def inspect_object(object)
        case object
        when Hash, Array
          object.inspect
        when ActionController::Base
          "#{object.controller_name}##{object.action_name}"
        else
          object.to_s
        end
      end

  end
end
