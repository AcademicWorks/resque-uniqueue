require 'helper'

class TestResqueUniqueue < Test::Unit::TestCase

  def setup
    Resque.instance_variable_set :@unique_queues, nil
    Resque.instance_variable_set :@unique_queues_enabled, nil
    Resque.instance_variable_set :@pop_unique_eval_sha, nil
    Resque.instance_variable_set :@push_unique_eval_sha, nil
    Resque.instance_variable_set :@queue_and_set_length_equal_eval_sha, nil
  end

  context "enabling gem" do
    
    should "be off by default" do
      refute Resque.unique_queues?
    end

    should "be able to be turned on" do
      Resque.stubs(:confirm_compatible_redis_version).returns true
      Resque.unique_queues!
      assert Resque.unique_queues?
    end

  end

  context "Redis version checking" do

    should "raise exception if pre 2.6.0" do
      redis = Object.new
      def redis.info
        {"redis_version" => '2.5.9'}
      end
      Resque.stubs(:redis).returns(redis)
      assert_raises(RuntimeError){ Resque.confirm_compatible_redis_version }
    end

    should "no raise an exception if 2.6.0 or later" do
      redis = Object.new
      def redis.info
        {"redis_version" => '2.6.0'}
      end
      Resque.stubs(:redis).returns(redis)
      assert_nil Resque.confirm_compatible_redis_version 
    end

  end

  context "setting queues" do

    setup do
      Resque.stubs(:queues).returns(['priority_10'])
    end

    should "default to all queues if non set" do      
      assert_equal Resque.unique_queues, ['priority_10']
    end

    should "be able to set specific queue list" do
      Resque.unique_queues = ['priority_20']
      assert_equal Resque.unique_queues, ['priority_20']
    end

  end

  context "deteriming if a queue is unique" do

    setup do
      Resque.unique_queues = ['priority_10']
    end

    should "no be unique if gem not enabled" do
      refute Resque.unique_queue?('priority_10')
    end

    should "be have unique queues when enabled" do
      Resque.stubs(:confirm_compatible_redis_version).returns true
      Resque.unique_queues!
      assert Resque.unique_queue?('priority_10')
    end

  end

  context "loading redis scripts" do

    should "load push_unique_eval_sha" do
      Resque.expects(:load_script).returns("12345")
      assert Resque.push_unique_eval_sha, "12345"
    end

    should "load pop_unique_eval_sha" do
      Resque.expects(:load_script).returns("12345")
      assert Resque.pop_unique_eval_sha, "12345"
    end

    should "load queue_and_set_length_equal_eval_sha" do
      Resque.expects(:load_script).returns("12345")
      assert Resque.queue_and_set_length_equal_eval_sha, "12345"
    end

    should "memoize push_unique_eval_sha" do
      Resque.stubs(:load_script).returns("12345")
      Resque.push_unique_eval_sha
      Resque.stubs(:load_script).returns("54321")
      assert Resque.push_unique_eval_sha, "12345"
    end

    should "memoize pop_unique_eval_sha" do
      Resque.stubs(:load_script).returns("12345")
      Resque.pop_unique_eval_sha
      Resque.stubs(:load_script).returns("54321")
      assert Resque.pop_unique_eval_sha, "12345"
    end

    should "memoize queue_and_set_length_equal_eval_sha" do
      Resque.stubs(:load_script).returns("12345")
      Resque.queue_and_set_length_equal_eval_sha
      Resque.stubs(:load_script).returns("54321")
      assert Resque.queue_and_set_length_equal_eval_sha, "12345"
    end

  end

  context "pushing & popping" do
    
    context "non-unique queues" do

      setup do
        Resque.stubs(:confirm_compatible_redis_version).returns true
        Resque.unique_queues!
        Resque.unique_queues=['priority_10']
      end

      should "call parent for push" do
        Resque.stubs(:push_unique).returns "failed"
        refute_equal Resque.push('priority_20', {'name' => 'bob'}), "failed"
      end

      should 'call parent for pop' do
        Resque.stubs(:pop_unique).returns "failed"
        refute_equal Resque.pop('priority_20'), "failed"
      end

    end

    context 'remove_queue' do

      setup do
        Resque.redis.flushall
        Resque.unique_queues!
        Resque.unique_queues= ['priority_10']
      end

      should 'work for normal queues' do
        Resque.push('priority_20', {'name' => 'bob'})
        assert Resque.redis.exists('queue:priority_20')
        Resque.remove_queue('priority_20')
        refute Resque.redis.exists 'queue:priority_20'
      end

      should 'work for unique queues' do
        Resque.push('priority_10', {'name' => 'bob'})
        assert Resque.redis.exists('queue:priority_10')
        assert Resque.redis.exists('queue:priority_10:uniqueue')
        Resque.remove_queue('priority_10')
        refute Resque.redis.exists 'queue:priority_10'
        refute Resque.redis.exists 'queue:priority_10:uniqueue'
      end

    end

    context "unique queues" do

      setup do
        Resque.stubs(:confirm_compatible_redis_version).returns true
        Resque.unique_queues!
        Resque.unique_queues=['priority_10']
      end

      should "call push_unique for push" do
        Resque.stubs(:push_unique).returns "success"
        assert_equal Resque.push('priority_10', {'name' => 'bob'}), "success"
      end

      should 'call pop_unique for pop' do
        Resque.stubs(:pop_unique).returns "success"
        assert_equal Resque.pop('priority_10'), "success"
      end

    end

    context "confirm_unique_queue_validity" do

      setup do
        Resque.redis.flushall
      end

      should "return true if set length and list length are the same" do
        Resque.redis.sadd   "priority_10:uniqueue", "test"
        Resque.redis.rpush  "priority_10", "test"
        Resque.confirm_unique_queue_validity("priority_10")
      end

      should 'raise exception if length of set and list differ' do
        Resque.redis.rpush  "priority_10", "test"
        assert_raises(RuntimeError){ Resque.confirm_unique_queue_validity("priority_10") }
      end

    end

    context "queue names" do
      
      setup do
        Resque.redis.flushall
      end

      should "maintain same queue name between unique and non unique" do
        assert_equal Resque.queues.size, 0
        refute Resque.unique_queues?
        Resque.push('priority_20', {'name' => 'bob'})
        queues =  Resque.queues
        Resque.redis.flushall
        Resque.unique_queues!
        Resque.unique_queues= ['priority_20']
        Resque.push('priority_20', {'name' => 'bob'})
        assert_equal queues, Resque.queues
        assert_equal queues.size, 1
      end

    end

    context 'scripting logic' do

      setup do
        Resque.redis.flushall
        Resque.unique_queues!
        Resque.unique_queues= ['priority_10']
      end

      context 'push_unique' do

        should 'create set & list if they do not exist' do
          refute Resque.redis.exists 'queue:priority_10'
          refute Resque.redis.exists 'queue:priority_10:uniqueue'
          Resque.push('priority_10', {'name' => 'bob'})
          assert Resque.redis.exists 'queue:priority_10'
          assert Resque.redis.exists 'queue:priority_10:uniqueue'
        end

        should "add items to set and list if message unique" do
          Resque.push('priority_10', {'name' => 'bob'})
          assert_equal Resque.redis.llen('queue:priority_10'), 1
          assert_equal Resque.redis.scard('queue:priority_10:uniqueue'), 1
        end

        should "not add item to queue if already on there" do
          Resque.push('priority_10', {'name' => 'bob'})
          assert_equal Resque.redis.llen('queue:priority_10'), 1
          assert_equal Resque.redis.scard('queue:priority_10:uniqueue'), 1
          Resque.push('priority_10', {'name' => 'bob'})
          assert_equal Resque.redis.llen('queue:priority_10'), 1
          assert_equal Resque.redis.scard('queue:priority_10:uniqueue'), 1
        end

        should "return queue length if unique job" do
          assert_equal Resque.push('priority_10', {'name' => 'bob'}), 1
          assert_equal Resque.push('priority_10', {'name' => 'robert'}), 2
        end

        should "return nil if duplicate job" do
          assert_equal Resque.push('priority_10', {'name' => 'bob'}), 1
          assert_nil Resque.push('priority_10', {'name' => 'bob'})
        end

      end

      context "pop_unique" do

        should "return same item whether unique queue or not" do
          Resque.push('priority_20', {'name' => 'bob'})
          job = Resque.pop('priority_20')
          Resque.push('priority_10', {'name' => 'bob'})
          uniqueue_job = Resque.pop('priority_10')
          assert_equal job, uniqueue_job
        end

        should "return same item whether unique queue or not when queue is empty" do
          job = Resque.pop('priority_20')
          uniqueue_job = Resque.pop('priority_10')
          assert_equal job, uniqueue_job
        end

        should 'remove job from list and set' do
          Resque.push('priority_10', {'name' => 'bob'})
          assert_equal Resque.redis.llen('queue:priority_10'), 1
          assert_equal Resque.redis.scard('queue:priority_10:uniqueue'), 1
          Resque.pop('priority_10')
          assert_equal Resque.redis.llen('queue:priority_10'), 0
          assert_equal Resque.redis.scard('queue:priority_10:uniqueue'), 0
        end

      end

    end

  end

end
