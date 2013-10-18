# resque-uniqueue

### Why use Uniqueue?

Multiple identical jobs are wasteful. Uniqueue ensures that *for a given queue*, identical jobs are never enqueued, and you can stress a little less about your application code causing duplicate work.

### Prerequisites
Uniqueue uses Lua scripting, which requires **Redis 2.6 or greater**, so make sure your Redis installation is up to date.

Before deploying an application with Uniqueue enabled for the first time, it's important that you **ensure your queues are empty**.

### Installation
Add Uniqueue to your Gemfile.

    gem 'resque-uniqueue'
    
Then run bundle install within your app's directory.

### Configuration
You'll need to configure Uniqueue somewhere in your application's initialization process. If you are running a Rails application it's recommended you use your Resque initializer:

    # config/initializers/resque.rb
    Resque.unique_queues!

#### Specifying queues 
By default Uniqueue defaults to preventing identical jobs on all queues. However, if you need to scope Uniqueue to specific queues, then your intializer code should look like this:

    # config/initializers/resque.rb
    Resque.unique_queues = ["emails", "orders"] 
    Resque.unique_queues!

### How It Works

Uniqueue overrides 3 resque commands: `push`, `pop`, and `remove_queue` in order to enforce *queue-level uniqueness* of jobs. And for each queue two additional Redis keys are created:

1. `queue:[queue_name]:uniqueue` - A **set** containing MultiJSON dumps of the payload of all items on the queue
2. `queue:[queue_name]:start_at` - A **list** containing the Unix timestamp of each job on the queue's start time, ordered identically to the actual job queue

Now when Resque pushes a job the following happens:

1. The length/cardinality of the queue, uniqueue set, and start_at list are verified to be equal. If they aren't, stuff has gone bad, and you'll get an exception.
2. A Lua script is evaluated that executes `sadd` on the payload (well, a MultiJSON dump of it), which will add it to the uniqueue set if it is not already a member.
3. If the payload's dump was not previously stored in the set, we `rpush` the start time of the job to the start_at list and `rpush` the job to the queue (following the lead of Resque's default `push` command).

Because the three operations happen in the context of a Lua script, atomicity is guaranteed (See "Atomicity of Scripts" [here][eval]), and race conditions can never cause the uniqueue set, start_at list, and original queue to get out of sync. Each unique job is now successfully queued, its payload is present in our uniqueue set, and its start_at timestamp is on a list that corresponds exactly to the order of the queue list.

Popping a job is very similar:

1. Lengths and cardinalities are verified.
2. MultiJSON load the payload.
3. Return the payload with an additional key of 'start_at', which is the Unix timestamp that the job began.

And this is how a unique job is born.

### Contributing

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet.
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it.
* Fork the project.
* Start a feature/bugfix branch.
* Commit and push until you are happy with your contribution.
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.

### Copyright

Copyright (c) 2013 AcademicWorks, inc. See LICENSE.txt for
further details.

[eval]: http://redis.io/commands/eval