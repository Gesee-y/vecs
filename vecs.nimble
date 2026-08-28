packageName   = "vecs"
version       = "0.0.1"
author        = "Row"
description   = "Vexel's ECS"
license       = "MIT"

srcDir        = "src"
binDir        = "bin"
skipFiles     = @[]

requires "nim >= 2.0.0"
requires "cborious"

task test, "Run the test suite":
  exec "nim r test/timmediate.nim"
  exec "nim r test/tdeferred.nim"
  exec "nim r test/tafter.nim"
  exec "nim r test/tqueries.nim"
  exec "nim r test/tid.nim"
  exec "nim r test/tecsseq.nim"
  exec "nim r test/tcomponents.nim"
  exec "nim r test/tevents.nim"
  exec "nim r -d:ArchetypeWords=2 test/tmanycomponents.nim 2>&1"
  exec "nim r test/torder.nim"
  exec "nim r test/tsnapshots.nim"
  exec "nim r test/taddworld.nim"
  exec "nim r test/serialization/tsimpletext.nim"
  exec "nim r test/serialization/tsimplebinary.nim"
  exec "nim r test/serialization/tcompositetext.nim"
  exec "nim r test/serialization/tcompositebinary.nim"

task docs, "Generate documentation":
  exec "nim doc --project --git.url:git@github.com:RowDaBoat/vecs.git --index:on --outdir:docs src/vecs.nim"
