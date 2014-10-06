module Timeline::Track
  extend ActiveSupport::Concern

  module ClassMethods

    def track(name,options={})
      @name = name
      @callback = options.delete :on
      @callback ||= :create
      @actor = options.delete :actor
      @actor ||= :creator
      @actor_attributes = options.delete :actor_attributes
      @object = options.delete :object
      @object_attributes = options.delete :object_attributes
      @target = options.delete :target
      @target_attributes = options.delete :target_attributes
      @followers = options.delete :followers
      @followers ||= :followers
      @mentionable = options.delete :mentionable
      method_name = "track_#{@name}_after_#{@callback}".to_sym
      define_activity_method method_name, actor: @actor,actor_attributes: @actor_attributes, object: @object, object_attributes: @object_attributes, target: @target,target_attributes: @target_attributes, followers: @followers, verb: name, mentionable: @mentionable

      send "after_#{@callback}".to_sym, method_name, if: options.delete(:if)
    end

    private
    def abort? param
      if param == false
        false
      else
        true
      end
    end

    def define_activity_method(method_name, options={})
      define_method method_name do
        @actor = send(options[:actor])
        @actor_attributes = options[:actor_attributes]
        @fields_for = {}
        @object = set_object(options[:object])
        @object_attributes = options[:object_attributes]
        @target = !options[:target].nil? ? send(options[:target].to_sym) : nil
        @target_attributes = options[:target_attributes]
        @extra_fields ||= nil
        @followers = prepare_followers(options[:followers])
        @mentionable = options[:mentionable]
        add_activity activity(verb: options[:verb],attr: {actor:@actor_attributes, object:@object_attributes, target:@target_attributes})
      end
    end
  end

  protected
  def activity(options={})
    {
      verb: options[:verb],
      actor: options_for(@actor, options[:attr][:actor]),
      object: options_for(@object, options[:attr][:object]),
      target: options_for(@target,options[:attr][:target]),
      created_at: Time.now
    }
  end

  def add_activity(activity_item)
    redis_add "global:activity", activity_item
    add_activity_to_user(activity_item[:actor][:id], activity_item)
    add_activity_by_user(activity_item[:actor][:id], activity_item)
    add_mentions(activity_item)
    add_activity_to_followers(activity_item) if @followers.any?
  end

  def add_activity_by_user(user_id, activity_item)
    redis_add "user:id:#{user_id}:posts", activity_item
  end

  def add_activity_to_user(user_id, activity_item)
    redis_add "user:id:#{user_id}:activity", activity_item
  end

  def add_activity_to_followers(activity_item)
    @followers.each { |follower| add_activity_to_user(follower.id, activity_item) }
  end

  def add_mentions(activity_item)
    return unless @mentionable and @object.send(@mentionable)
    @object.send(@mentionable).scan(/@\w+/).each do |mention|
      if user = @actor.class.find_by_username(mention[1..-1])
        add_mention_to_user(user.id, activity_item)
      end
    end
  end

  def add_mention_to_user(user_id, activity_item)
    redis_add "user:id:#{user_id}:mentions", activity_item
  end

  def extra_fields_for(object)
    return {} unless @fields_for.has_key?(object.class.to_s.downcase.to_sym)
    @fields_for[object.class.to_s.downcase.to_sym].inject({}) do |sum, method|
      sum[method.to_sym] = @object.send(method.to_sym)
      sum
    end
  end

  def options_for(target, target_attr)
    case
      when !target.nil? && target_attr.nil?
        {
          id: target.id,
          class: target.class.to_s,
        }
      when !target.nil? && !target_attr.nil?
        result_hash= {}
        target_attr.map do |element|
          result = target.send element.to_s
          result_hash[element] = result
        end
        {
          id: target.id,
          class: target.class.to_s,
          attributes: result_hash
        }
      else
        nil
    end
  end

  def set_object(object)
    if object.is_a?(Symbol)
      send(object)
    else
      self
    end
  end

  def redis_add(list, activity_item)
    Timeline.redis.lpush list, Timeline.encode(activity_item)
  end

  def extract_from_follower(param)
    if param.is_a? Array
      param.join '.'
    else
      param.to_s
    end
  end

  def extract_class_from_follower(param)
    if param.is_a? Array
      param.first.to_s.capitalize.constantize
    else
      param.to_s.capitalize.constantize
    end
  end

  def prepare_followers(param)
    result = instance_eval(extract_from_follower(param))
    if result.is_a?(Array)
      result
    else
      [result]
    end

  end


end
