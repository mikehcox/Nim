import rawsockets, asyncdispatch, macros
var p = newDispatcher()
var sock = newAsyncRawSocket()

proc convertReturns(node, retFutureSym: PNimrodNode): PNimrodNode {.compileTime.} =
  case node.kind
  of nnkReturnStmt:
    result = newCall(newIdentNode("complete"), retFutureSym, node[0])
  else:
    result = node
    for i in 0 .. <node.len:
      result[i] = convertReturns(node[i], retFutureSym)

macro async2(prc: stmt): stmt {.immediate.} =
  expectKind(prc, nnkProcDef)

  var outerProcBody = newNimNode(nnkStmtList)

  # -> var retFuture = newFuture[T]()
  var retFutureSym = newIdentNode("retFuture") #genSym(nskVar, "retFuture")
  outerProcBody.add(
    newVarStmt(retFutureSym, 
      newCall(
        newNimNode(nnkBracketExpr).add(
          newIdentNode("newFuture"),
          prc[3][0][1])))) # Get type from return type of this proc.

  # -> iterator nameIter(): PFutureBase {.closure.} = <proc_body>
  # Changing this line to: newIdentNode($prc[0].ident & "Iter") # will make it work.
  var iteratorNameSym = genSym(nskIterator, $prc[0].ident & "Iter")
  #var iteratorNameSym = newIdentNode($prc[0].ident & "Iter")
  var procBody = prc[6].convertReturns(retFutureSym)

  var closureIterator = newProc(iteratorNameSym, [newIdentNode("PFutureBase")],
                                procBody, nnkIteratorDef)
  closureIterator[4] = newNimNode(nnkPragma).add(newIdentNode("closure"))
  outerProcBody.add(closureIterator)

  # -> var nameIterVar = nameIter
  # -> var first = nameIterVar()
  var varNameIterSym = newIdentNode($prc[0].ident & "IterVar") #genSym(nskVar, $prc[0].ident & "IterVar")
  var varNameIter = newVarStmt(varNameIterSym, iteratorNameSym)
  outerProcBody.add varNameIter
  var varFirstSym = genSym(nskVar, "first")
  var varFirst = newVarStmt(varFirstSym, newCall(varNameIterSym))
  outerProcBody.add varFirst


  result = prc

  # Remove the 'closure' pragma.
  for i in 0 .. <result[4].len:
    if result[4][i].ident == !"async":
      result[4].del(i)

  result[6] = outerProcBody

proc readStuff(): PFuture[string] {.async2.} =
  var fut = connect(sock, "irc.freenode.org", TPort(6667))
  yield fut
  var fut2 = recv(sock, 50)
  yield fut2
  return fut2.read
