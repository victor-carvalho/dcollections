module dcollections.smallvector;

import core.stdc.string: memmove;
import core.lifetime: move, moveEmplace;
import dcollections.utils.lifetime: shouldDestroy;
import std.algorithm.comparison: max;
import std.experimental.allocator.mallocator: Mallocator;
import std.experimental.allocator.common: stateSize;
import std.range.primitives: hasLength, isInputRange, ElementType;

struct SmallVector(T, size_t bytes = 4096, Allocator = Mallocator) {
    static if (stateSize!Allocator == 0) {
        this(size_t size) {
            if (size > stackLength)
                initHeap(size);
        }
    } else {
        this(size_t size, Allocator allocator) {
            this.allocator = move(allocator);
            if (size > stackLength)
                initHeap(size);
        }
    }

    ~this() {
        clear();
        if (buffer != null) {
            allocator.deallocate(cast(void[])(buffer));
        }   
    }

    void shrinkToFit() {
        if (!isInStack) {
            auto oldBuffer = cast(void[])(buffer);
            allocator.reallocate(oldBuffer, len * T.sizeof);
            buffer = cast(T[])(oldBuffer);
        }
    }

    void reserve(size_t additional) {
        if (isInStack) {
            auto requested = len + additional;
            if (requested > stackLength)
                initHeap(calculateCapacity(stackLength, requested));
        } else {
            reserveHeap(additional);
        }
    }

    void clear() {
        static if (shouldDestroy!T) {
            auto ptr = bufferPtr();
            foreach (i; 0..len) {
                ptr[i].__xdtor();
            }
        }
        len = 0;
    }

    void insertBack(T item) {
        auto ptr = prepareBuffer();
        moveEmplace(item, ptr[len++]);
    }

    void insertFront(T item) {
        auto ptr = prepareBuffer();
        memmove(ptr + 1, ptr, len * T.sizeof);
        moveEmplace(item, ptr[0]);
        len++;
    }

    void insert(size_t index, T item) {
        boundsCheck(len, index);
        auto ptr = prepareBuffer();
        memmove(ptr + index + 1, ptr + index, (len - index) * T.sizeof);
        moveEmplace(item, ptr[index]);
        len++;
    }

    void insertAt(R)(size_t index, R range) if (isInputRange!R) {
        boundsCheck(len, index);
        static if (hasLength!R) {
            auto ptr = prepareBuffer(range.length);
            memmove(ptr + index + range.length, ptr + index, (len - index) * T.sizeof);
            auto idx = index;
            foreach(item; range)
                moveEmplace(item, ptr[idx++]);
            len += range.length;
        } else {
            foreach(item; range)
                vector.insert(index, item);
        }
    }

    void append(R)(R range) if (isInputRange!R) {
        static if (hasLength!R) {
            auto ptr = prepareBuffer(range.length);
            foreach(item; range)
                moveEmplace(item, ptr[len++]);
        } else {
            foreach(item; range)
                vector.insertBack(item);
        }
    }

    void prepend(R)(R range) if (isInputRange!R) {
        static if (hasLength!R) {
            auto ptr = prepareBuffer(range.length);
            memmove(ptr + range.length, ptr, range.length * T.sizeof);
            auto idx = 0;
            foreach(item; range) {
                moveEmplace(item, ptr[idx++]);
            }
            len += range.length;
        } else {
            foreach(ref item; range)
                vector.insertFront(item);
        }
    }

    @property scope ref T back() {
        validateEmptyAccess!"back"(len);
        auto ptr = bufferPtr();
        return ptr[len-1];
    }

    @property scope ref T front() {
        validateEmptyAccess!"front"(len);
        auto ptr = bufferPtr();
        return ptr[0];
    }

    T removeBack() {
        validateEmptyAccess!"back"(len);
        auto ptr = bufferPtr();
        len--;
        T result = void;
        moveEmplace(ptr[len], result);
        return result;
    }

    T removeFront() {
        validateEmptyAccess!"front"(len);
        auto ptr = bufferPtr();
        len--;
        T result = void;
        moveEmplace(ptr[0], result);
        memmove(ptr, ptr + 1, len * T.sizeof);
        return result;
    }

    T remove(size_t index) {
        boundsCheck(len, index);
        auto ptr = bufferPtr();
        len--;
        T result = void;
        moveEmplace(ptr[index], result);
        memmove(ptr + index, ptr + index +  1, (len - index) * T.sizeof);
        return result;
    }

    void remove(size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        auto ptr = bufferPtr();
        static if (shouldDestroy!T) {
            foreach (i; start..end) {
                ptr[i].__xdtor();
            }
        }
        memmove(ptr + start, ptr + end, (len - end) * T.sizeof);
        len = len - (end - start);
    }

    scope ref T opIndex(size_t index) {
        boundsCheck(len, index);
        auto ptr = bufferPtr();
        return ptr[index];
    }

    scope ref T opIndexAssign(T value, size_t index) {
        boundsCheck(len, index);
        auto ptr = bufferPtr();
        move(value, ptr[index]);
        return ptr[index];
    }

    scope T[] opSlice() {
        auto ptr = bufferPtr();
        return ptr[0..len];
    }

    scope T[] opSlice(size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        auto ptr = bufferPtr();
        return ptr[start..end];
    }

    scope T[] opSliceAssign(T value, size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        auto ptr = bufferPtr();
        ptr[start..end] = value;
        return ptr[start..end];
    }

    scope T[] opSliceAssign(T[] slice, size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        assert(slice.length == (end - start));
        auto ptr = bufferPtr();
        ptr[start..end] = slice;
        return ptr[start..end];
    }

    pragma(inline, true)
    @property bool empty() {
        return len == 0;
    }

    pragma(inline, true)
    @property size_t opDollar() {
        return len;
    }

    pragma(inline, true)
    @property size_t length() {
        return len;
    }

    pragma(inline, true)
    @property size_t capacity() {
        return isInStack ? stackLength : buffer.length;
    }

    pragma(inline)
    bool isInStack() {
        return buffer == null;
    }
private:
    pragma(inline, true)
    void initHeap(size_t size) {
        buffer = cast(T[])(allocator.allocate(size * T.sizeof));
    }

    pragma(inline, true)
    void reserveHeap(size_t additional) {
        reserveExactHeap(calculateCapacity(capacity, capacity + additional));
    }

    void reserveExactHeap(size_t newCap) {
        assert(capacity <= newCap, "trying to reserve less than capacity");
        auto oldBuffer = cast(void[])(buffer);
        allocator.reallocate(oldBuffer, newCap * T.sizeof);
        buffer = cast(T[])(oldBuffer);
    }

    pragma(inline)
    T* bufferPtr() {
        return isInStack ? cast(T*)(stackBuffer.ptr) : buffer.ptr;
    }

    T* prepareBuffer(size_t additional = 1) {
        if (isInStack) {
            const requested = len + additional;
            if (requested > stackLength) {
                initHeap(calculateCapacity(stackLength, requested));
                return buffer.ptr;
            }
            return cast(T*)(stackBuffer.ptr);
        }
        if (len == buffer.length)
            reserveHeap(1);
        return buffer.ptr;
    }

    enum stackLength = bytes / T.sizeof;

    T[] buffer;
    align(T.alignof) ubyte[stackLength * T.sizeof] stackBuffer = void;
    size_t len;
    static if (stateSize!Allocator == 0)
        alias allocator = Allocator.instance;
    else
        Allocator allocator;
}

private size_t calculateCapacity(size_t old, size_t requested) {
    return max(requested, old * 2);
}

pragma(inline, true)
private void boundsCheck(size_t len, size_t index) {
    version(D_NoBoundsChecks) {
    } else {
        import std.format: format;
        version (LDC) {
            import ldc.intrinsics : llvm_expect;
            if (llvm_expect(index >= len, false))
                assert(false, format("index %d not in 0..%d", index, len));
        } else {
            if (index >= len)
                assert(false, format("index %d not in 0..%d", index, len));
        }
    }
}

pragma(inline, true)
private void boundsCheckSlice(size_t len, size_t start, size_t end) {
    version(D_NoBoundsChecks) {
    } else {
        import std.format: format;
        version (LDC) {
            import ldc.intrinsics : llvm_expect;
            if (llvm_expect(start >= len || end >= len, false))
                assert(false, format("asked for %d..%d from 0..%d", start, end, len));
        } else {
            if (start >= len || end >= len)
                assert(false, format("asked for %d..%d from 0..%d", start, end, len));
        }
    }
}

pragma(inline, true)
private void validateEmptyAccess(string method)(size_t length) {
    version (LDC) {
        import ldc.intrinsics : llvm_expect;
        if (llvm_expect(length == 0, false))
            assert(false, "trying to access " ~ method ~ " of empty collection");
    } else {
        if (length == 0)
            assert(false, "trying to access " ~ method ~ " of empty collection");
    }
}

auto smallVector(R)(R range) if (isInputRange!R) {
    static if (hasLength!R)
        auto vec = SmallVector!(ElementType!R)(range.length);
    else
        auto vec = SmallVector!(ElementType!R).init;
    foreach(ref item; range)
        vec.insertBack(item);
    return vec;
}

@("vector")
unittest {
    import std.range: iota;
    
    auto v1 = smallVector(iota(5));
    
    assert(v1.length == 5);
    assert(v1.isInStack);
    assert(v1.capacity == 1024);
    assert(v1[] == [0,1,2,3,4]);
}

@("Vetor.this")
unittest {
    SmallVector!int v1;
    assert(v1.empty);

    import std.experimental.allocator.showcase: StackFront;

    SmallVector!(int, 4096, StackFront!1028) v2;
    assert(v2.empty);

    StackFront!1028 a;
    auto v3 = SmallVector!(int, 4096, StackFront!1028)(0, move(a));
    assert(v3.empty);
}

@("Vector.reserve")
unittest {
    SmallVector!int v1;
    v1.reserve(10);
    assert(v1.empty);
    assert(v1.isInStack);
    assert(v1.capacity == 1024);

    v1.reserve(2000);
    assert(v1.empty);
    assert(!v1.isInStack);
    assert(v1.capacity == 2048);
}

@("Vector.clear")
unittest {
    auto v1 = SmallVector!int(10);
    v1.insertBack(1);
    v1.insertBack(2);

    v1.clear();
    assert(v1.empty);
    assert(v1.capacity == 1024);
}

@("Vector.shrinkToFit")
unittest {
    auto v1 = SmallVector!int(10);
    v1.insertBack(1);
    v1.insertBack(2);

    v1.shrinkToFit();
    assert(v1.capacity == 1024);
}

@("Vector.insertBack")
unittest {
    SmallVector!int v1;
    v1.insertBack(1);
    assert(v1.back == 1);
    assert(v1.length == 1);
    
    v1.insertBack(2);
    assert(v1.back == 2);
    assert(v1.length == 2);

    v1.insertBack(3);
    assert(v1.back == 3);
    assert(v1.length == 3);

    assert(v1[] == [1,2,3]);
}

@("Vector.insertFront")
unittest {
    SmallVector!int v1;
    v1.insertFront(1);
    assert(v1.front == 1);
    assert(v1.length == 1);
    
    v1.insertFront(2);
    assert(v1.front == 2);
    assert(v1.length == 2);

    v1.insertFront(3);
    assert(v1.front == 3);
    assert(v1.length == 3);

    assert(v1[] == [3,2,1]);
}

@("Vector.insert")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;
    v1.insert(2,10);
    assert(v1[2] == 10);
    assert(v1.length == 6);

    v1.insert(4, 20);
    assert(v1[4] == 20);
    assert(v1.length == 7);
    
    assert(v1[] == [0,1,10,2,20,3,4]);
}

@("Vector.removeBack")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    assert(v1.removeBack == 4);
    assert(v1.length == 4);

    assert(v1.removeBack == 3);
    assert(v1.length == 3);

    assert(v1[] == [0,1,2]);
}

@("Vector.removeFront")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    assert(v1.removeFront == 0);
    assert(v1.length == 4);

    assert(v1.removeFront == 1);
    assert(v1.length == 3);

    assert(v1[] == [2,3,4]);
}

@("Vector.remove")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    assert(v1.remove(1) == 1);
    assert(v1.length == 4);

    assert(v1.remove(2) == 3);
    assert(v1.length == 3);

    assert(v1[] == [0,2,4]);

    auto v2 = iota(10).smallVector;

    v2.remove(1,4);
    assert(v2.length == 7);
    assert(v2[] == [0,4,5,6,7,8,9]);
}

@("Vector.opIndex")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    assert(v1[1] == 1);

    v1[1] = 10;

    assert(v1[1] == 10);
}

@("Vector.opSlice")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    assert(v1[1..4] == [1,2,3]);

    v1[1..4] = 2;

    assert(v1[1..4] == [2,2,2]);
    
    v1[1..4] = [2,3,4];

    assert(v1[1..4] == [2,3,4]);
}

@("Vector.append")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    v1.append(iota(5, 10));
    assert(v1[] == [0,1,2,3,4,5,6,7,8,9]);
    assert(v1.length == 10);
}

@("Vector.append")
unittest {
    import std.range: iota;

    auto v1 = iota(5, 10).smallVector;

    v1.prepend(iota(5));

    assert(v1[] == [0,1,2,3,4,5,6,7,8,9]);
    assert(v1.length == 10);
}

@("Vector.insertAt")
unittest {
    import std.range: iota;

    auto v1 = iota(5).smallVector;

    v1.insertAt(1, [10,10,10]);

    assert(v1.length == 8);
    assert(v1[] == [0,10,10,10,1,2,3,4]);

    v1.insertAt(5, [20,20]);

    assert(v1.length == 10);
    assert(v1[] == [0,10,10,10,1,20,20,2,3,4]);
}