# Compressed swap in RAM (zram): idle memory gets compressed instead of programs being
# killed when RAM runs out. Takes RAM only for what's actually swapped out.
{
  zramSwap.enable = true;
}
