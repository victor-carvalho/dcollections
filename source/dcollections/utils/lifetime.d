module dcollections.utils.lifetime;

enum shouldDestroy(T) = is(T == struct) && __traits(hasMember, T, "__xdtor");
