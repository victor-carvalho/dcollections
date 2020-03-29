module dcollections.circularqueue;

import core.stdc.string: memcpy;
import core.lifetime: move, moveEmplace;
import dcollections.utils.lifetime: shouldDestroy;
import dcollections.utils.numbers: nextPowerOfTwo;
import std.algorithm.comparison: max;
import std.experimental.allocator.mallocator: Mallocator;
import std.experimental.allocator.common: stateSize;
import std.range.primitives: hasLength, isInputRange, ElementType;

struct CircularQueue(T, Allocator = Mallocator) {
    static if (stateSize!Allocator == 0) {
        this(size_t size) {
            init(size);
        }
    } else {
        this(size_t size, Allocator allocator) {
            this.allocator = allocator;
            init(size);
        }
    }

    ~this() {
        if (data != null) {
            clear();
            allocator.deallocate(cast(void[])(data));
        }   
    }

    pragma(inline, true)
    void reserve(size_t additional) {
        reserveUnchecked(calculateCapacity(capacity, additional));
    }

    pragma(inline, true)
    void reserveExact(size_t newCap) {
        reserveUnchecked(newCap.nextPowerOfTwo);
    }

    void insertBack(T item) {
        growIfNeeded();
        auto old = head;
        moveEmplace(item, data[old]);
        head = wrapIndex(head + 1, capacity);
    }

    void insertFront(T item) {
        growIfNeeded();
        tail = wrapIndex(tail - 1, capacity);
        moveEmplace(item, data.ptr[tail]);
    }

    scope ref T front() {
        validateEmptyAccess!"front"(length);
        return data.ptr[tail];
    }

    scope ref T back() {
        validateEmptyAccess!"back"(length);
        return data.ptr[wrapIndex(head - 1, capacity)];
    }

    T removeBack() {
        validateEmptyAccess!"back"(length);
        T result = void;
        head = wrapIndex(head - 1, capacity);
        moveEmplace(data.ptr[head], result);
        return result;
    }

    T removeFront() {
        validateEmptyAccess!"front"(length);
        auto old = tail;
        T result = void;
        moveEmplace(data.ptr[old], result);
        tail = wrapIndex(tail + 1, capacity);
        return result;
    }

    void clear() {
        static if (shouldDestroy!T) {
            foreach (i; 0..head) {
                data.ptr[i].__xdtor();
            }
            foreach (i; tail..capacity) {
                data.ptr[i].__xdtor();
            }
        }
        head = 0;
        tail = 0;
    }

    pragma(inline, true)
    @property bool empty() {
        return head == tail;
    }

    pragma(inline, true)
    @property bool full() {
        return (capacity - length) == 1;
    }

    pragma(inline, true)
    @property size_t length() {
        return wrapIndex(head - tail, capacity);
    }

    pragma(inline, true)
    @property size_t capacity() {
        return data.length;
    }
private:
    void init(size_t size) {
        auto cap = size.nextPowerOfTwo;
        data = cast(T[])(allocator.allocate(cap * T.sizeof));
    }

    void growIfNeeded() {
        if (full)
            reserve(1);
    }

    void reserveUnchecked(size_t newCap) {
        auto oldCap = capacity;
        auto oldData = cast(void[])(data);
        allocator.reallocate(oldData, newCap * T.sizeof);
        data = cast(T[])(oldData);
        afterReserve(oldCap);
    }

    void afterReserve(size_t oldCap) {
        if (tail <= head)
            return;
        auto delta = oldCap - tail;
        if (head < delta) {
            memcpy(data.ptr + oldCap, data.ptr, head * T.sizeof);
            head += oldCap;
        } else {
            auto newTail = capacity - delta;
            memcpy(data.ptr + newTail, data.ptr + tail, delta * T.sizeof);
            tail = capacity - delta;
        }
    }

    T[] data;
    size_t head;
    size_t tail;
    static if (stateSize!Allocator == 0)
        alias allocator = Allocator.instance;
    else
        Allocator allocator;
}

pragma(inline, true)
private size_t wrapIndex(size_t index, size_t capacity) {
    return index & (capacity - 1);
}

pragma(inline, true)
private size_t calculateCapacity(size_t old, size_t additional) {
    auto requested = (old + additional).nextPowerOfTwo;
    if (old == 0)
        return max(requested, 4);
    else
        return requested;
}

pragma(inline, true)
private void validateEmptyAccess(string method)(size_t length) {
    if (length == 0)
        assert(false, "trying to access " ~ method ~ " of empty circular buffer");
}

unittest {
    import core.stdc.stdio: printf;

    auto queue = CircularQueue!int(10);

    queue.insertBack(1);
    queue.insertBack(2);
    queue.insertBack(3);
    queue.insertBack(4);
    queue.insertBack(5);
    
    assert(queue.length == 5);
    assert(queue.capacity == 16);

    assert(queue.removeBack == 5);
    assert(queue.removeBack == 4);
    assert(queue.removeBack == 3);
    assert(queue.removeBack == 2);
    assert(queue.removeBack == 1);

    assert(queue.empty);
    assert(queue.length == 0);
    assert(queue.capacity == 16);

    queue.insertFront(1);
    queue.insertFront(2);
    queue.insertFront(3);
    queue.insertFront(4);
    queue.insertFront(5);

    assert(queue.length == 5);
    assert(queue.capacity == 16);

    assert(queue.removeFront == 5);
    assert(queue.removeFront == 4);
    assert(queue.removeFront == 3);
    assert(queue.removeFront == 2);
    assert(queue.removeFront == 1);

    assert(queue.empty);
    assert(queue.length == 0);
    assert(queue.capacity == 16);

    queue.insertBack(1);
    assert(queue.front == queue.back);

    queue.insertFront(2);
    assert(queue.front == 2);
    assert(queue.back == 1);

    assert(!queue.empty);
    queue.clear();
    assert(queue.empty);
}