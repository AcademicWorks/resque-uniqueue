require 'resque'

module Resque
  module Uniqueue
    
    def push(queue, item)
      unique_queue?(queue) ? push_unique(queue, item) : super
    end
    
    def pop(queue)
      unique_queue?(queue) ? pop_unique(queue)        : super
    end

    def push_unique(queue, item)
      confirm_unique_queue_validity(queue)
      watch_queue(queue)
      redis.evalsha push_unique_eval_sha, [queue], [encode(item)]
    end

    def pop_unique(queue)
      confirm_unique_queue_validity(queue)
      decode redis.evalsha pop_unique_eval_sha, [queue]
    end

    def push_unique_eval_sha
      @push_unique_eval_sha ||= load_script <<-LUA
        local list_name = KEYS[1]
        local set_name = list_name..':uniqueue'
        local in_set = redis.call('sadd', set_name , ARGV[1])
        if in_set == 1 then
          return redis.call('rpush', list_name, ARGV[1])
        end
        return false
      LUA
    end

    def pop_unique_eval_sha
      @pop_unique_eval_sha  ||= load_script <<-LUA
        local list_name = KEYS[1]
        local set_name = list_name..':uniqueue'
        local job = redis.call('lpop', list_name)
        redis.call('srem', set_name, job)
        return job
      LUA
    end

    def queue_and_set_length_equal_eval_sha
      @queue_and_set_length_equal_eval_sha ||= load_script <<-LUA
        local list_name = KEYS[1]
        local set_name = list_name..':uniqueue'
        local list_size = redis.call('llen', list_name)
        local set_size = redis.call('scard', set_name)
        return list_size == set_size
      LUA
    end

    def load_script(script)
      redis.script :load, script
    end

    #if the queue and set sizes differ, something is very wrong and we should fail loudly
    def confirm_unique_queue_validity(queue)
      response =  redis.evalsha queue_and_set_length_equal_eval_sha, [queue]
      return true if response == 1
      #TODO raise specific exception
      raise "Make sure your queues are empty before you start using uniqueue"
    end

    #is this queue a unique queue
    def unique_queue?(queue)
      unique_queues? && unique_queues.include?(queue)
    end

    #list the unique queues
    def unique_queues
      @unique_queues || queues
    end

    #set a specific list of unique queues
    def unique_queues=(unique_queues)
      @unique_queues = unique_queues
    end

    #turn on unique queues
    def unique_queues!
      confirm_compatible_redis_version
      @unique_queues_enabled = true
    end

    #are unique queues turned on?
    def unique_queues?
      !!@unique_queues_enabled
    end

    def confirm_compatible_redis_version
      redis_version = redis.info["redis_version"]
      major, minor, patch = redis_version.split('.').map(&:to_i)
      if major < 2 || minor < 6
        #TODO raise specific exception
        raise "Redis version must be at least 2.6.0 you are running #{redis_version}"
      end
    end

  end
end

Resque.send(:extend, Resque::Uniqueue)