module vision.eventbus;

import core.time : msecs, seconds, Duration;
import vibe.core.task;
import vibe.core.core : sleep;
import std.conv : to;

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
    shared Bus bus; ///< bus subscribed to

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
    struct SubscribeEvent
    {
        Task subscriber;
    }

    struct UnsubscribeEvent
    {
        Task subscriber;
    }

    struct StopEvent
    {
    };

    private SubscriberIdent[string] subscribers;

    /// Emit stop event for bus
    void stop()
    {
        emit(StopEvent());
    }

    ~this()
    {
        stop;
        while (subscribers.length)
            sleep(50.msecs); // can't do subscribers.values[0].task.join; because of sharedness problems
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

        shared(Unqual!EventType) sharedEvent = cast(shared Unqual!EventType) event;

        foreach (ref subscriber; subscribers)
        {
            subscriber.task.send(sharedEvent);
        }
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
            receive((shared(Bus.StopEvent) e) { exit = true; }, delegates);
    });
}

/**
 * Receive events until timeout is reached or provided delegate will return true.
 * Used to wait for specific event.
 * If you interested in events of different types use Variant for delegate parameter.
 */
bool receiveTimeoutUntil(T)(Duration timeout, T op)
{
    import core.time: MonoTime;
    import std.traits: Parameters;
    import vibe.core.concurrency : receiveTimeout;

    MonoTime end = MonoTime.currTime() + timeout;

    bool result = false;

    while (!result)
        if (!receiveTimeout(end - MonoTime.currTime(), (Parameters!op event) {
                result = op(event);
            }))
            break;
            
    return result;
}

unittest
{
    import vibe.core.concurrency;
    import std.range : iota;
    import std.typecons : scoped;
    import std.variant;
    import std.stdio;
    import std.conv : to;
    import vibe.core.core : yield, runTask;

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
    version (none) auto logger = bus.subscribeDelegates((Variant e) {
        debug
        {
            writeln("Arrived: ", e);
            stdout.flush;
        }
    });

    enum TASKS = 2;
    enum EVENTS = 50;

    int[3] eventAmount;

    // subscribe custom listeners
    foreach (i; iota(0, TASKS))
        bus.subscribeDelegates((shared Custom1 e) { ++eventAmount[0]; }, (shared Custom2 e) {
            ++eventAmount[1];
        }, (shared Custom3 e) { ++eventAmount[2]; });

    yield();
    assert(bus.tasksAmount() == TASKS,
            "Expected " ~ TASKS.to!string ~ " tasks, in fact " ~ bus.tasksAmount().to!string);

    // generate random events
    import std.random;

    foreach (i; iota(0, EVENTS))
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

    bus.destroy;

    import std.algorithm : sum;

    assert(eventAmount[].sum == EVENTS * TASKS);

    /*/
	import std.stdio;

	struct Ping
	{
		int n;
	}
	struct Pong
	{
		int n;
	}

	// another test

	writeln("New bus");stdout.flush;
	bus = new shared Bus();

	auto rr = bus.subscribeDelegates((shared Ping p){ sleep(1.seconds); if(p.n<4) bus.emit(Pong(p.n)); });

	bus.emit(shared Pong(555));


	runTask(()
	{
		for(int i=1000;i<1010;++i)
		{
			bus.emit(shared Pong(i));
			sleep(500.msecs);
		}
	});


	auto s = runTask(() 
	{
        	auto subscription = bus.subscribeMe();

        	bool exit = false;

		for(int cnt=1; cnt<5; ++cnt)
		{
			bus.emit(shared Ping(cnt));
			writeln("emit Ping(",cnt,")");
			if(!receiveTimeoutUntil(2.seconds, (shared Pong p){writeln("recv Pong(",p.n,")"); return p.n == cnt;}))
			{
				writeln("exit by timeout");
				break;
			}
		}
	});

	s.join();
	bus.destroy;
	//*/
}
