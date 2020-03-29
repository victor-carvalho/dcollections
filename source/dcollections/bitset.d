module dcollections.bitset;

import core.bitop;

struct StaticBitset(size_t n) {
    void set(T: size_t)(T value) {
        assert(value < n);
        data[value >> BIT_SHIFT] |= (1 << (value & BIT_MASK));
    }

    void reset(T: size_t)(T value) {
        assert(value < n);
        data[value >> BIT_SHIFT] &= ~(1 << (value & BIT_MASK));
    }

    bool contains(T: size_t)(T value) {
        assert(value < n);
        return (data[value >> BIT_SHIFT] & (1 << (value & BIT_MASK))) > 0;
    }

    bool opIndex(T: size_t)(T value) {
        assert(value < n);
        return (data[value >> BIT_SHIFT] & (1 << (value & BIT_MASK))) > 0;
    }

    pragma(inline, true)
    @property size_t length() {
        return n;
    }
private:
    alias BUCKET = ulong;
    enum BUCKET_SIZE = BUCKET.sizeof << 3;
    enum BIT_SHIFT = bsr(BUCKET_SIZE);
    enum BIT_MASK = BUCKET_SIZE - 1;
    BUCKET[n >> BIT_SHIFT] data;
}
