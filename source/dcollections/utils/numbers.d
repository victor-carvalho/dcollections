module dcollections.utils.numbers;

pragma(inline, true)
size_t nextPowerOfTwo(size_t value) {
    if (value == 0)
        return 1;
    version(LDC) {
        import ldc.intrinsics: llvm_ctlz;
        return (size_t.max >> llvm_ctlz(value, true)) + 1;
    } else {
        import core.bitop: bsr;
        return 1 << (bsr(value) + 1);
    }
}
