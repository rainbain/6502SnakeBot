# Watermellon, By Samuel Fitzsimons (rainbain)
This is a classic snake bot written in 256 bytes.
Its actually 255, but I then added an extra 0x69 to make it 256.

## Result
```
Game Over!
  Score:                       125.611229
  Total Ticks:                 18620
  Last Iteration Clock Cycles: 464
  Total Clock Cycles:          37026190
```

Code Size: 256 bytes.

## How It Works
This bot simply just follows a predetermined path.
But if it sees that it can skip a section of the path thats empty,
that is contains no snake or food, it takes it.

This makes it so that it will get to the food a bit faster, while
not going into a state where it could crash.

This is usually how I play snake, with one difference.
This was a 17x17 board, so there is always that one space left open.
I opted to just alternated between 2 paths, as to not miss anything that could land in that space.

A lot went into packing it into 256 bytes. The first was 293 bytes. I copied a lot to zeropage to make lookups smaller, and remove some redundant path parts. (The repeated path to get the missing space.)

I also went into more evil 6502 optimizations, like replacing unconditional jumps with conditional jumps that act unconditional. Since they are 2 bytes and not 3 bytes.