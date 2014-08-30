module Timeline::Actor
  extend ActiveSupport::Concern

  included do
    def timeline(options={})
      Timeline.get_list(timeline_options(options)).map do |item|
        Timeline::Activity.new Timeline.decode(item)
      end
    end

    def timeline_delete(options={})
      Timeline.remove_list(remove_from_timeline_options(options))
    end

    def followers
      []
    end

    private
    def timeline_options(options)
      defaults = { list_name: "user:id:#{self.id}:activity", start: 0, end: 19 }
      if options.is_a? Hash
        defaults.merge!(options)
      elsif options.is_a? Symbol
        case options
          when :global
            defaults.merge!(list_name: "global:activity")
          when :posts
            defaults.merge!(list_name: "user:id:#{self.id}:posts")
          when :mentions
            defaults.merge!(list_name: "user:id:#{self.id}:mentions")
        end
      end
    end

    def remove_from_timeline_options(options)
      unless options.include? :first and options.include? :last

        if options.include? :first and Float(options[:first])
          { list_name: "user:id:#{self.id}:activity", start: 0, end: (options[:first] * -1) - 1 }
        elsif options.include? :last and Float(options[:last])
          { list_name: "user:id:#{self.id}:activity", start: options[:last] + 1, end: -1 }
        else
          { list_name: "user:id:#{self.id}:activity", start: -1, end: 0 }
        end

      end
    end

  end
end