module dcollections.vector;

import core.stdc.string: memmove;
import core.lifetime: move, moveEmplace;
import dcollections.utils.lifetime: shouldDestroy;
import std.algorithm.comparison: max;
import std.experimental.allocator.mallocator: Mallocator;
import std.experimental.allocator.common: stateSize;
import std.range.primitives: hasLength, isInputRange, ElementType;

struct Vector(T, Allocator = Mallocator) {
    static if (stateSize!Allocator == 0) {
        this(size_t size) {
            init(size);
        }
    } else {
        this(size_t size, Allocator allocator) {
            this.allocator = move(allocator);
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
        reserveExact(calculateCapacity(capacity, additional));
    }

    void reserveExact(size_t newCap) {
        assert(capacity <= newCap, "trying to reserve less than capacity");
        auto oldData = cast(void[])(data);
        allocator.reallocate(oldData, newCap * T.sizeof);
        data = cast(T[])(oldData);
    }

    void shrinkToFit() {
        auto oldData = cast(void[])(data);
        allocator.reallocate(oldData, len * T.sizeof);
        data = cast(T[])(oldData);
    }

    void clear() {
        static if (shouldDestroy!T) {
            foreach (i; 0..len) {
                data.ptr[i].__xdtor();
            }
        }
        len = 0;
    }

    void insertBack(T item) {
        growIfNeeded();
        moveEmplace(item, data[len++]);
    }

    void insertFront(T item) {
        growIfNeeded();
        memmove(data.ptr + 1, data.ptr, len * T.sizeof);
        moveEmplace(item, data.ptr[0]);
        len++;
    }

    void insert(size_t index, T item) {
        boundsCheck(len, index);
        growIfNeeded();
        memmove(data.ptr + index + 1, data.ptr + index, (len - index) * T.sizeof);
        moveEmplace(item, data.ptr[index]);
        len++;
    }

    void insertAt(R)(size_t index, R range) if (isInputRange!R) {
        boundsCheck(len, index);
        static if (hasLength!R) {
            growIfNeeded(range.length);
            memmove(data.ptr + index + range.length, data.ptr + index, (len - index) * T.sizeof);
            auto idx = index;
            foreach(item; range)
                moveEmplace(item, data.ptr[idx++]);
            len += range.length;
        } else {
            foreach(item; range)
                vector.insert(index, item);
        }
    }

    void append(R)(R range) if (isInputRange!R) {
        static if (hasLength!R) {
            growIfNeeded(range.length);
            foreach(item; range)
                moveEmplace(item, data.ptr[len++]);
        } else {
            foreach(item; range)
                vector.insertBack(item);
        }
    }

    void prepend(R)(R range) if (isInputRange!R) {
        static if (hasLength!R) {
            growIfNeeded(range.length);
            memmove(data.ptr + range.length, data.ptr, range.length * T.sizeof);
            auto idx = 0;
            foreach(item; range) {
                moveEmplace(item, data.ptr[idx++]);
            }
            len += range.length;
        } else {
            foreach(ref item; range)
                vector.insertFront(item);
        }
    }

    @property scope ref T back() {
        validateEmptyAccess!"back"(len);
        return data.ptr[len-1];
    }

    @property scope ref T front() {
        validateEmptyAccess!"front"(len);
        return data.ptr[0];
    }

    T removeBack() {
        validateEmptyAccess!"back"(len);
        len--;
        T result = void;
        moveEmplace(data.ptr[len], result);
        return result;
    }

    T removeFront() {
        validateEmptyAccess!"front"(len);
        len--;
        T result = void;
        moveEmplace(data.ptr[0], result);
        memmove(data.ptr, data.ptr + 1, len * T.sizeof);
        return result;
    }

    T remove(size_t index) {
        boundsCheck(len, index);
        len--;
        T result = void;
        moveEmplace(data.ptr[index], result);
        memmove(data.ptr + index, data.ptr + index +  1, (len - index) * T.sizeof);
        return result;
    }

    void remove(size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        static if (shouldDestroy!T) {
            foreach (i; start..end) {
                data.ptr[i].__xdtor();
            }
        }
        memmove(data.ptr + start, data.ptr + end, (len - end) * T.sizeof);
        len = len - (end - start);
    }

    scope ref T opIndex(size_t index) {
        boundsCheck(len, index);
        return data.ptr[index];
    }

    scope ref T opIndexAssign(T value, size_t index) {
        boundsCheck(len, index);
        move(value, data.ptr[index]);
        return data.ptr[index];
    }

    scope T[] opSlice() {
        return data.ptr[0..len];
    }

    scope T[] opSlice(size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        return data.ptr[start..end];
    }

    scope T[] opSliceAssign(T value, size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        data.ptr[start..end] = value;
        return data.ptr[start..end];
    }

    scope T[] opSliceAssign(T[] slice, size_t start, size_t end) {
        boundsCheckSlice(len, start, end);
        assert(slice.length == (end - start));
        data.ptr[start..end] = slice;
        return data.ptr[start..end];
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
        return data.length;
    }
private:
    void init(size_t size) {
        data = cast(T[])(allocator.allocate(size * T.sizeof));
    }

    void growIfNeeded() {
        if (len < capacity)
            return;
        reserve(1);
    }

    void growIfNeeded(size_t additional) {
        auto requested = len + additional;
        if (requested <= capacity)
            return;
        reserve(requested - len);
    }

    T[] data;
    size_t len;
    static if (stateSize!Allocator == 0)
        alias allocator = Allocator.instance;
    else
        Allocator allocator;
}

private size_t calculateCapacity(size_t old, size_t additional) {
    auto requested = old + additional;
    if (old == 0)
        return max(requested, 4);
    else
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
    if (length == 0)
        assert(false, "trying to access " ~ method ~ " of empty collection");
}

auto vector(R)(R range) if (isInputRange!R) {
    static if (hasLength!R)
        auto vec = Vector!(ElementType!R)(range.length);
    else
        auto vec = Vector!(ElementType!R).init;
    foreach(ref item; range)
        vec.insertBack(item);
    return vec;
}

@("vector")
unittest {
    import std.range: iota;
    
    auto v1 = vector(iota(5));
    
    assert(v1.length == 5);
    assert(v1.capacity == 5);
    assert(v1[] == [0,1,2,3,4]);
}

@("Vetor.this")
unittest {
    Vector!int v1;
    assert(v1.empty);

    import std.experimental.allocator.showcase: StackFront;

    Vector!(int, StackFront!1028) v2;
    assert(v2.empty);

    StackFront!1028 a;
    auto v3 = Vector!(int, StackFront!1028)(0, move(a));
    assert(v3.empty);
}

@("Vector.reserve")
unittest {
    Vector!int v1;
    v1.reserve(10);
    assert(v1.empty);
    assert(v1.capacity == 10);

    v1.reserve(5);
    assert(v1.empty);
    assert(v1.capacity == 20);

    v1.reserve(30);
    assert(v1.empty);
    assert(v1.capacity == 50);
}

@("Vector.reserveExact")
unittest {
    Vector!int v1;
    v1.reserveExact(10);
    assert(v1.empty);
    assert(v1.capacity == 10);

    v1.reserveExact(15);
    assert(v1.empty);
    assert(v1.capacity == 15);
}

@("Vector.clear")
unittest {
    auto v1 = Vector!int(10);
    v1.insertBack(1);
    v1.insertBack(2);

    v1.clear();
    assert(v1.empty);
    assert(v1.capacity == 10);
}

@("Vector.shrinkToFit")
unittest {
    auto v1 = Vector!int(10);
    v1.insertBack(1);
    v1.insertBack(2);

    v1.shrinkToFit();
    assert(v1.capacity == 2);
}

@("Vector.insertBack")
unittest {
    Vector!int v1;
    v1.reserveExact(2);
    v1.insertBack(1);
    assert(v1.back == 1);
    assert(v1.length == 1);
    assert(v1.capacity == 2);
    
    v1.insertBack(2);
    assert(v1.back == 2);
    assert(v1.length == 2);
    assert(v1.capacity == 2);

    v1.insertBack(3);
    assert(v1.back == 3);
    assert(v1.length == 3);
    assert(v1.capacity == 4);

    assert(v1[] == [1,2,3]);
}

@("Vector.insertFront")
unittest {
    import core.stdc.stdio: printf;

    Vector!int v1;
    v1.reserveExact(2);
    v1.insertFront(1);
    assert(v1.front == 1);
    assert(v1.length == 1);
    assert(v1.capacity == 2);
    
    v1.insertFront(2);
    assert(v1.front == 2);
    assert(v1.length == 2);
    assert(v1.capacity == 2);

    v1.insertFront(3);
    assert(v1.front == 3);
    assert(v1.length == 3);
    assert(v1.capacity == 4);

    assert(v1[] == [3,2,1]);
}

@("Vector.insert")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;
    v1.insert(2,10);
    assert(v1[2] == 10);
    assert(v1.length == 6);
    assert(v1.capacity == 10);

    v1.insert(4, 20);
    assert(v1[4] == 20);
    assert(v1.length == 7);
    assert(v1.capacity == 10);
    
    assert(v1[] == [0,1,10,2,20,3,4]);
}

@("Vector.removeBack")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    assert(v1.removeBack == 4);
    assert(v1.length == 4);
    assert(v1.capacity == 5);

    assert(v1.removeBack == 3);
    assert(v1.length == 3);
    assert(v1.capacity == 5);

    assert(v1[] == [0,1,2]);
}

@("Vector.removeFront")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    assert(v1.removeFront == 0);
    assert(v1.length == 4);
    assert(v1.capacity == 5);

    assert(v1.removeFront == 1);
    assert(v1.length == 3);
    assert(v1.capacity == 5);

    assert(v1[] == [2,3,4]);
}

@("Vector.remove")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    assert(v1.remove(1) == 1);
    assert(v1.length == 4);
    assert(v1.capacity == 5);

    assert(v1.remove(2) == 3);
    assert(v1.length == 3);
    assert(v1.capacity == 5);

    assert(v1[] == [0,2,4]);

    auto v2 = iota(10).vector;

    v2.remove(1,4);
    assert(v2.length == 7);
    assert(v2.capacity == 10);
    assert(v2[] == [0,4,5,6,7,8,9]);
}

@("Vector.opIndex")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    assert(v1[1] == 1);

    v1[1] = 10;

    assert(v1[1] == 10);
}

@("Vector.opSlice")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    assert(v1[1..4] == [1,2,3]);

    v1[1..4] = 2;

    assert(v1[1..4] == [2,2,2]);
    
    v1[1..4] = [2,3,4];

    assert(v1[1..4] == [2,3,4]);
}

@("Vector.append")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    v1.append(iota(5, 10));
    assert(v1[] == [0,1,2,3,4,5,6,7,8,9]);
    assert(v1.length == 10);
}

@("Vector.append")
unittest {
    import std.range: iota;

    auto v1 = iota(5, 10).vector;

    v1.prepend(iota(5));

    assert(v1[] == [0,1,2,3,4,5,6,7,8,9]);
    assert(v1.length == 10);
}

@("Vector.insertAt")
unittest {
    import std.range: iota;

    auto v1 = iota(5).vector;

    v1.insertAt(1, [10,10,10]);

    assert(v1.length == 8);
    assert(v1[] == [0,10,10,10,1,2,3,4]);

    v1.insertAt(5, [20,20]);

    assert(v1.length == 10);
    assert(v1[] == [0,10,10,10,1,20,20,2,3,4]);
}
