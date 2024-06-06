//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   9 Aug 2022  Brian Frank  Creation
//

using util
using concurrent
using xeto
using haystack::Dict

**
** RSpec is the remote loader AST of a spec during decoding phase
**
@Js
internal class RSpec : CSpec, NameDictReader
{
  new make(Str libName, XetoSpec asm, RSpec? parent, Int nameCode, Str name)
  {
    this.libName  = libName
    this.asm      = asm
    this.parent   = parent
    this.isType   = parent == null && !name[0].isLower
    this.isGlobal = parent == null && name[0].isLower
    this.name     = name
    this.nameCode = nameCode
  }

  const Str libName
  const override XetoSpec asm
  const override Str name
  const Int nameCode
  RSpec? parent { private set }
  const override Bool isType
  const override Bool isGlobal

  // decoded by XetoBinaryReader
  RSpecRef? baseIn
  RSpecRef? typeIn
  NameDict? metaOwnIn
  NameDict? metaIn
  RSpec[]? slotsOwnIn
  RSpecRef[]? slotsInheritedIn

  // RemoteLoader.loadSpec
  Bool isLoaded
  CSpec? type
  CSpec? base
  MNameDict? metaOwn
  MNameDict? meta
  MSlots? slotsOwn
  MSlots? slots
  SpecFactory? factoryRef

  override Bool hasSlots() { !slots.isEmpty }

  // CSpec
  override Bool isAst() { true }
  override Str qname()
  {
    if (parent != null) return parent.qname + "." + name
    return libName + "::" + name
  }
  override haystack::Ref id() { throw UnsupportedErr() }
  override SpecFactory factory() { factoryRef ?: throw Err("Factory not assigned") }
  override CSpec ctype() { type }
  override CSpec? cbase
  override CSpec? cparent() { parent }
  override MNameDict cmeta() { meta ?: throw Err(name) }
  override CSpec? cslot(Str name, Bool checked := true) { throw UnsupportedErr() }
  override Void cslots(|CSpec, Str| f) { slots.each |s| { f((CSpec)s, s.name) } }
  override CSpec? cenum(Str key, Bool checked := true) { throw UnsupportedErr() }
  override Bool cisa(CSpec x) { XetoUtil.isa(this, x) }
  override CSpec[]? cofs
  override Str toStr() { name }
  override MSpecArgs args := MSpecArgs.nil  // TODO

  override final Bool isSys() { libName =="sys" }

  // flags
  override Int flags
  override Bool isScalar()    { hasFlag(MSpecFlags.scalar) }
  override Bool isMarker()    { hasFlag(MSpecFlags.marker) }
  override Bool isChoice()    { hasFlag(MSpecFlags.choice) }
  override Bool isDict()      { hasFlag(MSpecFlags.dict) }
  override Bool isList()      { hasFlag(MSpecFlags.list) }
  override Bool isMaybe()     { hasFlag(MSpecFlags.maybe) }
  override Bool isQuery()     { hasFlag(MSpecFlags.query) }
  override Bool isFunc()      { hasFlag(MSpecFlags.func) }
  override Bool isInterface() { hasFlag(MSpecFlags.interface) }
  override Bool isNone()      { hasFlag(MSpecFlags.none) }
  override Bool isSelf()      { hasFlag(MSpecFlags.self) }
  override Bool isEnum()      { hasFlag(MSpecFlags.enum) }
  override Bool isAnd()       { hasFlag(MSpecFlags.and) }
  override Bool isOr()        { hasFlag(MSpecFlags.or) }
  Bool hasFlag(Int mask) { flags.and(mask) != 0 }

  // NameDictReader to iterate slotsOwnIn
  override Int readName() { slotsOwnIn[readIndex].nameCode }
  override Obj? readVal() { slotsOwnIn[readIndex++].asm }
  private Int readIndex

}

**************************************************************************
** RSpecRef
**************************************************************************

@Js
internal const class RSpecRef
{
  new make(Int lib, Int type, Int slot, Int[]? more)
  {
    this.lib  = lib
    this.type = type
    this.slot = slot
    this.more = more
  }

  const Int lib       // lib name
  const Int type      // top-level type name code
  const Int slot      // first level slot or zero if type only
  const Int[]? more   // slot path below first slot (uncommon)

  override Str toStr() { "$lib $type $slot $more" }
}

