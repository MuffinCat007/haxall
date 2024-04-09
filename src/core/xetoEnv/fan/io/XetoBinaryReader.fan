//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   8 Aug 2023  Brian Frank  Creation
//

using concurrent
using util
using xeto
using haystack::Etc
using haystack::Marker
using haystack::NA
using haystack::Remove
using haystack::Number
using haystack::Ref
using haystack::Coord
using haystack::Symbol
using haystack::Dict
using haystack::Grid
using haystack::GridBuilder

**
** Reader for Xeto binary encoding of specs and data
**
** NOTE: this encoding is not backward/forward compatible - it only
** works with XetoBinaryWriter of the same version
**
@Js
class XetoBinaryReader : XetoBinaryConst, NameDictReader
{

//////////////////////////////////////////////////////////////////////////
// Constructor
//////////////////////////////////////////////////////////////////////////

  internal new make(XetoBinaryIO io, InStream in)
  {
    this.io = io
    this.names = io.names
    this.in = in
  }

//////////////////////////////////////////////////////////////////////////
// Remote Env Bootstrap
//////////////////////////////////////////////////////////////////////////

  internal RemoteNamespace readBoot(RemoteLibLoader? libLoader)
  {
    verifyU4(magic, "magic")
    verifyU4(version, "version")
    readNameTable
    libVersions := readLibVersions(libLoader)
    return RemoteNamespace(io, names, libVersions, libLoader) |ns->XetoLib|
    {
      sysLib := readLib(ns)
      verifyU4(magicEnd, "magicEnd")
      return sysLib
    }
  }

  private Void readNameTable()
  {
    max := readVarInt
    for (i := NameTable.initSize+1; i<=max; ++i)
      names.add(in.readUtf)
  }

  private LibVersion[] readLibVersions(RemoteLibLoader? libLoader)
  {
    num := readVarInt
    acc := LibVersion[,]
    acc.capacity = num
    num.times { acc.add(readLibVersion) }
    return acc
  }

  private LibVersion readLibVersion()
  {
    verifyU4(magicLibVer, "magic lib version")

    name := names.toName(readName)
    version := (Version)readVal

    dependsSize := readVarInt
    depends := LibDepend[,]
    depends.capacity = dependsSize
    dependsSize.times
    {
      depends.add(LibDepend(names.toName(readName)))
    }

    return RemoteLibVersion(name, version, depends)
  }

//////////////////////////////////////////////////////////////////////////
// Lib
//////////////////////////////////////////////////////////////////////////

  XetoLib readLib(MNamespace ns)
  {
    lib := XetoLib()

    verifyU4(magicLib, "magicLib")
    nameCode  := readName
    meta      := readMeta
    loader    := RemoteLoader(ns, nameCode, meta)
    readTops(loader)
    readInstances(loader)
    verifyU4(magicLibEnd, "magicLibEnd")

    return loader.loadLib
  }

  private Void readTops(RemoteLoader loader)
  {
    while (true)
    {
      nameCode := readName
      if (nameCode < 0) break
      x := loader.addTop(nameCode)
      readSpec(loader, x)
    }
  }

  private Void readSpec(RemoteLoader loader, RSpec x)
  {
    x.baseIn     = readSpecRef
    x.typeIn     = readSpecRef
    x.metaOwnIn  = ((MNameDict)readMeta).wrapped
    x.slotsOwnIn = readOwnSlots(loader, x)
    x.flags      = readVarInt
    if (read == XetoBinaryConst.specInherited)
    {
      x.metaIn = ((MNameDict)readMeta).wrapped
      x.slotsInheritedIn = readInheritedSlotRefs
    }
  }

  private RSpec[]? readOwnSlots(RemoteLoader loader, RSpec parent)
  {
    size := readVarInt
    if (size == 0) return null
    acc := RSpec[,]
    acc.capacity = size
    size.times
    {
      name := readName
      x := loader.makeSlot(parent, name)
      readSpec(loader, x)
      acc.add(x)
    }
    return acc
  }

  private RSpecRef[] readInheritedSlotRefs()
  {
    acc := RSpecRef[,]
    while (true)
    {
      ref := readSpecRef
      if (ref == null) break
      acc.add(ref)
    }
    return acc
  }

  private RSpecRef? readSpecRef()
  {
    // first byte is slot path depth:
    //  - 0: null
    //  - 1: top-level type like "foo::Bar"
    //  - 2: slot under type like "foo::Bar.baz"
    //  - 3: "foo::Bar.baz.qux"

    depth := read
    if (depth == 0) return null

    lib  := readName
    type := readName
    slot := 0
    Int[]? more := null
    if (depth > 1)
    {
      slot = readName
      if (depth > 2)
      {
        moreSize := depth - 3
        more = Int[,]
        more.capacity = moreSize
        moreSize.times { more.add(readName) }
      }
    }

    return RSpecRef(lib, type, slot, more)
  }

  private Void readInstances(RemoteLoader loader)
  {
    while (true)
    {
      ctrl := read
      if (ctrl == 0) break
      Dict x := doReadVal(ctrl)
      loader.addInstance(x)
    }
  }

//////////////////////////////////////////////////////////////////////////
// Values
//////////////////////////////////////////////////////////////////////////

  Dict readDict()
  {
    val := readVal
    if (val is Dict) return val
    throw IOErr("Expecting dict, not $val.typeof")
  }

  override Obj? readVal()
  {
    doReadVal(in.readU1)
  }

  private Obj? doReadVal(Int ctrl)
  {
    switch (ctrl)
    {
      case ctrlNull:         return null
      case ctrlMarker:       return Marker.val
      case ctrlNA:           return NA.val
      case ctrlRemove:       return Remove.val
      case ctrlTrue:         return true
      case ctrlFalse:        return false
      case ctrlName:         return names.toName(readName)
      case ctrlStr:          return readUtf
      case ctrlNumberNoUnit: return readNumberNoUnit
      case ctrlNumberUnit:   return readNumberUnit
      case ctrlInt2:         return in.readS2
      case ctrlInt8:         return in.readS8
      case ctrlFloat8:       return readF8
      case ctrlDuration:     return Duration(in.readS8)
      case ctrlUri:          return readUri
      case ctrlRef:          return readRef
      case ctrlDate:         return readDate
      case ctrlTime:         return readTime
      case ctrlDateTime:     return readDateTime
      case ctrlEmptyDict:    return Etc.dict0
      case ctrlNameDict:     return readNameDict
      case ctrlGenericDict:  return readGenericDict
      case ctrlSpecRef:      return readSpecRef // resolve to Spec later
      case ctrlList:         return readList
      case ctrlGrid:         return readGrid
      case ctrlVersion:      return readVersion
      case ctrlCoord:        return readCoord
      case ctrlSymbol:       return readSymbol
      default:               throw IOErr("obj ctrl 0x$ctrl.toHex")
    }
  }

  private Number readNumberNoUnit()
  {
    Number(readF8, null)
  }

  private Number readNumberUnit()
  {
    Number(readF8, Number.loadUnit(readUtf))
  }

  private Uri readUri()
  {
    Uri.fromStr(readUtf)
  }

  private Ref readRef()
  {
    Ref.make(readUtf, readUtf.trimToNull)
  }

  private Date readDate()
  {
    Date(in.readU2, Month.vals[in.read-1], in.read)
  }

  private Time readTime()
  {
    Time.fromDuration(Duration(in.readU4 * 1ms.ticks))
  }

  private DateTime readDateTime()
  {
    secs := in.readS4
    millis := in.readS2
    tz := TimeZone.fromStr(readVal)
    return DateTime.makeTicks(secs*1sec.ticks + millis*1ms.ticks, tz)
  }

  private Coord readCoord()
  {
    Coord.fromStr(readUtf)
  }

  private Symbol readSymbol()
  {
    Symbol.fromStr(readUtf)
  }

  private MNameDict readNameDict()
  {
    size := readVarInt
    return MNameDict(names.readDict(size, this))
  }

  private Dict readGenericDict()
  {
    acc := Str:Obj[:]
    while (true)
    {
      name := readVal.toStr
      if (name.isEmpty) break
      acc[name] = readVal
    }
    return haystack::Etc.dictFromMap(acc)
  }

  private Obj?[] readList()
  {
    size := readVarInt
    acc := Obj?[,]
    acc.capacity = size
    size.times |i| { acc.add(readVal) }
    return acc
  }

  private Grid readGrid()
  {
    numCols := readVarInt
    numRows := readVarInt

    gb := GridBuilder()
    gb.capacity = numRows
    gb.setMeta(readDict)
    for (c:=0; c<numCols; ++c)
    {
      gb.addCol(readVal, readDict)
    }
    for (r:=0; r<numRows; ++r)
    {
      cells := Obj?[,]
      cells.size = numCols
      for (c:=0; c<numCols; ++c)
        cells[c] = readVal
      gb.addRow(cells)
    }
    return gb.toGrid
  }

  private Version readVersion()
  {
    size := readVarInt
    segs := Int[,]
    segs.capacity = size
    for (i:=0; i<size; ++i) segs.add(readVarInt)
    return Version(segs)
  }

  override Int readName()
  {
    code := readVarInt
    if (code != 0) return code

    code = readVarInt
    name := readUtf
    names.set(code, name) // is now sparse
    return code
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  Int read()
  {
    in.readU1
  }

  Int readU4()
  {
    in.readU4
  }

  Int readS8()
  {
    in.readS8
  }

  Float readF8()
  {
    in.readF8
  }

  Str readUtf()
  {
    in.readUtf
  }

  Ref[] readRawRefList()
  {
    size := readVarInt
    acc := Ref[,]
    acc.capacity = size
    size.times { acc.add(Ref(readUtf)) }
    return acc
  }

  Dict[] readRawDictList()
  {
    size := readVarInt
    acc := Dict[,]
    acc.capacity = size
    size.times { acc.add(readDict) }
    return acc
  }

  private Dict readMeta()
  {
    verifyU1(ctrlNameDict, "ctrlNameDict for meta")  // readMeta is **with** the ctrl code
    return readNameDict
  }

  private Void verifyU1(Int expect, Str msg)
  {
    actual := in.readU1
    if (actual != expect) throw IOErr("Invalid $msg: 0x$actual.toHex != 0x$expect.toHex")
  }

  private Void verifyU4(Int expect, Str msg)
  {
    actual := readU4
    if (actual != expect) throw IOErr("Invalid $msg: 0x$actual.toHex != 0x$expect.toHex")
  }

  Int readVarInt()
  {
    v := in.readU1
    if (v == 0xff)           return -1
    if (v.and(0x80) == 0)    return v
    if (v.and(0xc0) == 0x80) return v.and(0x3f).shiftl(8).or(in.readU1)
    if (v.and(0xe0) == 0xc0) return v.and(0x1f).shiftl(8).or(in.readU1).shiftl(16).or(in.readU2)
    return in.readS8
  }

//////////////////////////////////////////////////////////////////////////
// Fields
//////////////////////////////////////////////////////////////////////////

  private const XetoBinaryIO io
  private const NameTable names
  private InStream in
}

