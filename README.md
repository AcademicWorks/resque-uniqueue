# resque-uniqueue

Multiple identical jobs are wasteful. Uniqueue ensures that *for a given queue*, identical jobs are never enqueued, and you can stress a little less about your application code causing duplicate work.

**Note:** Uniqueue uses Lua scripting, which requires Redis 2.6 or greater.

### Usage

    # somewhere in your application initialization:
    Resque.unique_queues = ["unique", "queues"]  # this step is optional, Uniqueue defaults to all queues
    Resque.unique_queues!

Usage is dead simple:

1. Ensure you're running Redis 2.6 or greater
2. Make sure your queues are totally empty
3. Enable Uniqueue in application code
4. Restart your app

In addition, you can optionally set only particular queues to be unique, but Uniqueue will default to ensuring all queues are unique.

### How It Works

Uniqueue overrides 3 resque commands: `push`, `pop`, and `remove_queue` in order to enforce *queue-level uniqueness* of jobs. And for each queue, two additional Redis keys are created:

1. `queue:[queue_name]:uniqueue` - A **set** containing MultiJSON dumps of the payload of all items on the queue
2. `queue:[queue_name]:start_at` - A **list** containing the Unix timestamp of each job on the queue's start time, ordered identically to the actual job queue

Then, when Resque pushes a job, the following happens:

1. The length/cardinality of the queue, uniqueue set, and start_at list are verified to be equal. If they aren't, stuff has gone bad, and you'll get an exception.
2. A Lua script is evaluated that executes `sadd` on the payload (well, a MultiJSON dump of it), which will add it to the uniqueue set if it is not already a member.
3. If the payload's dump was not previously stored in the set, we `rpush` the start time of the job to the start_at list and `rpush` the job to the queue (following the lead of Resque's default `push` command).

Because the three operations happen in the context of a Lua script, atomicity is guaranteed (See "Atomicity of Scripts" [here][eval]), and race conditions can never cause the uniqueue set, start_at list, and original queue to get out of sync. And, for each unique job, we now successfully have the job queued, its payload present in our uniqueue set, and its start_at on a list that corresponds exactly to the order of the queue list.

And popping a job is very similar:

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