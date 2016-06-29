require "resque"

module Resque
  module Uniqueue

    def push(queue, item)
      unique_queue?(queue) ? push_unique(queue, item) : super
    end

    def pop(queue)
      unique_queue?(queue) ? pop_unique(queue)        : super
    end

    def remove_queue(queue)
      super(queue)
      redis.del("queue:#{queue}:uniqueue")
      redis.del("queue:#{queue}:start_at")
    end

    def push_unique(queue, item, time = Time.now.utc.to_i)
      watch_queue(queue)
      queue = "queue:#{queue}"

      redis.evalsha push_unique_eval_sha, [queue], [encode(item), time]
    end

    def pop_unique(queue)
      queue = "queue:#{queue}"
      confirm_unique_queue_validity(queue)
      results = redis.evalsha pop_unique_eval_sha, [queue]
      return nil unless results[0]
      job = decode results[0]
      job["start_at"] ||= results[1].to_i
      return job
    end

    def push_unique_eval_sha
      @push_unique_eval_sha ||= load_script <<-LUA
        local queue_name = KEYS[1]
        local uniqueue_name = queue_name..':uniqueue'
        local start_at_name = queue_name..':start_at'
        local not_in_set = redis.call('sadd', uniqueue_name , ARGV[1])
        if not_in_set == 1 then
          redis.call('rpush', start_at_name, ARGV[2])
          return redis.call('rpush', queue_name, ARGV[1])
        end
        return false
      LUA
    end

    def pop_unique_eval_sha
      @pop_unique_eval_sha  ||= load_script <<-LUA
        local queue_name = KEYS[1]
        local uniqueue_name = queue_name..':uniqueue'
        local start_at_name = queue_name..':start_at'
        local results = {}
        results[1] = redis.call('lpop', queue_name)
        results[2] = redis.call('lpop', start_at_name)
        if results[1] then
          redis.call('srem', uniqueue_name, results[1])
        end
        return results
      LUA
    end

    def queue_and_set_length_equal_eval_sha
      @queue_and_set_length_equal_eval_sha ||= load_script <<-LUA
        local queue_name = KEYS[1]
        local uniqueue_name = queue_name..':uniqueue'
        local start_at_name = queue_name..':start_at'
        local queue_size = redis.call('llen', queue_name)
        local uniqueue_size = redis.call('scard', uniqueue_name)
        local start_at_size = redis.call('llen', start_at_name)
        if queue_size == uniqueue_size then
          if queue_size == start_at_size then
            return true
          end
        end
        return false
      LUA
    end

    def load_script(script)
      redis.script :load, script
    end

    #if the queue and set sizes differ, something is very wrong and we should fail loudly
    def confirm_unique_queue_validity(queue)
      response = redis.evalsha queue_and_set_length_equal_eval_sha, [queue]
      return true if response == 1
      #TODO raise specific exception
      raise "Make sure your queues are empty before you start using uniqueue"
    end

    #is this queue a unique queue
    #if you have uniqueue turned on and no queues are set, its assumes all queues are unique
    def unique_queue?(queue)
      return false unless unique_queues?
      !unique_queues || unique_queues.include?(queue)
    end

    #list the unique queues
    def unique_queues
      @unique_queues
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
      major, minor, patch = redis_version.split(".").map(&:to_i)
      if major < 2 || (major == 2 && minor < 6)
        #TODO raise specific exception
        raise "Redis version must be at least 2.6.0 you are running #{redis_version}"
      end
    end

  end
end

Resque.send(:extend, Resque::Uniqueue)
