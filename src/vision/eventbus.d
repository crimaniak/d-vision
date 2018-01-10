module vision.eventbus;

import vibe.core.task;

/**
 * Struct to identify subscribed task by cached hash string
 */
struct SubscriberIdent
{
    Task task; ///< task identified
    string id; ///< cached string identifier

    this(Task t)
    {
        task = t;
        id = getId(task);
    }

    static string getId(Task task)
    {
        import std.array : appender;

        auto result = appender!string;

        task.tid.toString((c) { result ~= c; });
        return result.data;
    }
}

/**
 * Subscribtion object with automatic unsubscribe in destructor
 */
struct Subscription
{
    SubscriberIdent subscriber; ///< subscriber 
    shared Bus bus;             ///< bus subscribed to
    
    /// Subscribe task to bus
    this(Task task, shared Bus bus)
    {
        subscriber = SubscriberIdent(task);
        this.bus = bus;
        this.bus.subscribe(subscriber);
    }

    ~this()
    {
        bus.unsubscribe(subscriber);
    }

	/// Gate for bus emit method
    public void emit(EventType)(EventType event)
    {
        bus.emit(event);
    }
}

/**
 * Event bus itself
 */
synchronized class Bus
{
	// Bus events
    struct SubscribeEvent { Task subscriber; }
    struct UnsubscribeEvent { Task subscriber; }
    immutable struct StopEvent {};
    
    private SubscriberIdent[string] subscribers;

	/// Emit stop event for bus
    void stop()
    {
        emit(StopEvent());
    }

    ~this()
    {
        stop;
    }

	/// Get number of tasks substribed for this bus
    ulong tasksAmount() const
    {
        return subscribers.length;
    }

	/// Emit event for bus
    void emit(EventType)(EventType event) @trusted
    {
        import vibe.core.concurrency : send;
        import std.traits : Unqual;

        auto sharedEvent = cast(shared Unqual!EventType) event;

        foreach (ref subscriber; subscribers)
            subscriber.task.send(sharedEvent);
    }

	/// Subscribe current task for this bus
    Subscription subscribeMe()
    {
        return subscribe(Task.getThis());
    }

	/// Subscribe given task for this bus
    Subscription subscribe(Task subscriberTask)
    {
        return Subscription(subscriberTask, this);
    }

	/// Subscrube subscriber for this bus
    void subscribe(SubscriberIdent subscriber)
    {
        subscribers[subscriber.id] = subscriber;
    }

	/// Unsubscrube subscriber from this bus
    void unsubscribe(SubscriberIdent subscriber)
    {
        subscribers.remove(subscriber.id);
    }

	/// check if given task is subscribed for this bus
    bool subscribed(Task task)
    {
        immutable id = SubscriberIdent(task).id;
        return cast(bool)(id in subscribers);
    }

}

/**
 * Subscribe task defined by the set of delegates
 * with automatic unsubscribe on StopEvent
 */
Task subscribeDelegates(D...)(shared Bus bus, D delegates)
{
    import vibe.core.core : runTask;
    import vibe.core.concurrency : receive;

    return runTask(() {
        auto subscription = bus.subscribeMe();

        bool exit = false;

        while (!exit)
            receive((shared Bus.StopEvent e) {
                exit = true;
            }, delegates);
    });
}

unittest
{
    import vibe.core.concurrency;
    import vibe.core.core;
    import core.time : msecs;
    import std.range : iota;
    import std.typecons : scoped;
    import std.variant;
    import std.stdio;

	// create bus
    shared Bus bus = new shared Bus();
    scope (exit)
        bus.destroy;
    
    // custom events for test    
    struct Custom1
    {
        int a;
    }

    struct Custom2
    {
        string a;
    }

    struct Custom3
    {
        string[] a;
    }

	// subscribe logger
    auto logger = bus.subscribeDelegates((Variant e) {
        writeln("Arrived: ", e);
        stdout.flush;
    });

    enum TASKS = 100;

	// subscribe custom listeners
    foreach (i; iota(0, TASKS))
        bus.subscribeDelegates
	        ((shared Custom1 e) {
	            writeln("c1:", e);
	            stdout.flush;
	        }
	        ,(shared Custom2 e) { 
	        	writeln("c2:", e); 
	        	stdout.flush; 
	        });
    /*
    runTask((){
      auto subscription = bus.subscribeMe();

      bool exit = false;

      while(!exit) receive(
        (Custom1 e){ writeln(e);stdout.flush; },
        (Custom2 e){ writeln(e);stdout.flush; },
        (Bus.StopEvent e){
          bus.emit(Custom2("task exit"));
          exit = true;
        }
      );
    });
*/
    sleep(100.msecs);
    assert(bus.tasksAmount() == TASKS + 1);

	// generate random events
    import std.random;
    foreach (i; iota(1, 50))
    {
        switch (uniform(1, 4))
        {
        case 1:
            bus.emit(Custom1(uniform(1, 100)));
            break;
        case 2:
            bus.emit(Custom2("custom2"));
            break;
        case 3:
            bus.emit(Custom3(["custom3", "a", "b"]));
            break;
        default:
            break;
        }
    }

    import vibe.core.core : yield;

    bus.stop;

    sleep(100.msecs); // don't help
    yield();		  // don't help
    logger.join();	  // stopped is here because StopEvent is not detected by receive() I think

}
