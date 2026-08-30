import unittest
include "../src/vseq.nim"

import std/sequtils

type
  A = object
    x: int

  B = object
    y: int
    a: ref A

proc addAndZero(v: VSeq[T], val: sink T) =
  let p = cast[ptr byte](addr val)
  let s = cast[pointer](addr v)
  s.unsafeAdd(p)

  zeroMem(p, sizeof(T))


