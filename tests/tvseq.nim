import unittest
include "../src/vseq.nim"

import std/sequtils

suite "Tests for VSeq":

  test "Initialization, Add, and Sequential Access":
    var v = newVSeqOfCap[int](2)
    v.add(10)
    v.add(20)
    v.add(30)
    
    check toSeq(v) == @[10, 20, 30]

  test "Insertion and Deletion":
    var v = newVSeqOfCap[int](2)
    v.add(10)
    v.add(20)
    v.add(30)

    v.insert(1, 99)
    check toSeq(v) == @[10, 99, 20, 30]

    v.delete(2)
    check toSeq(v) == @[10, 99, 30]

  test "Element Mutating and Popping":
    var v = newVSeqOfCap[int](2)
    v.add(10)
    v.add(99)
    v.add(30)

    v[0] = 42
    check v[0] == 42
    check toSeq(v) == @[42, 99, 30]

    check v.pop() == 30
    check toSeq(v) == @[42, 99]

  test "Copy and Move Semantics":
    var v = newVSeqOfCap[int](2)
    v.add(42)
    v.add(99)

    var w = v
    check toSeq(w) == @[42, 99]

    var z = move(v)
    check toSeq(z) == @[42, 99]
    check v.len == 0

  test "Unsafe Pointer Operations":
    var s = newVSeqOfCap[uint32](4)
    var p = addr s
    var raw: array[4, byte] = [0x01'u8, 0x02, 0x03, 0x04]

    unsafeAdd(p, addr raw[0])
    
    check s.len == 1