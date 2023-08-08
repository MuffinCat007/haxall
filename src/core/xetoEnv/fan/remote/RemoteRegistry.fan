//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   8 Aug 2022  Brian Frank  Creation
//

using util
using concurrent
using xeto
using haystack::UnknownLibErr

**
** RemoteRegistry implementation
**
@Js
internal const class RemoteRegistry : MRegistry
{
  new make(RemoteRegistryEntry[] list)
  {
    this.list = list
    this.map  = Str:RemoteRegistryEntry[:].addList(list) { it.name }
  }

  override RemoteRegistryEntry? get(Str qname, Bool checked := true)
  {
    x := map[qname]
    if (x != null) return x
    if (checked) throw UnknownLibErr("Not installed: $qname")
    return null
  }

  override Lib? load(Str qname, Bool checked := true)
  {
    // check for install
    entry := get(qname, checked)
    if (entry == null) return null

    // check for cached loaded lib
    if (entry.isLoaded) return entry.get

    // load from transport
    throw Err("TODO")
  }

  override Int build(LibRegistryEntry[] libs)
  {
    throw UnsupportedErr()
  }

  override const RemoteRegistryEntry[] list
  const Str:RemoteRegistryEntry map
}

**************************************************************************
** RemoteRegistryEntry
**************************************************************************

@Js
internal const class RemoteRegistryEntry : MRegistryEntry
{
  new make(Str name)
  {
    this.name = name
  }

  override const Str name

  override Version version() { Version.defVal }

  override Str doc() { "" }

  override Str toStr() { name }

  override File zip() { throw UnsupportedErr() }

  override Bool isSrc() { false }

  override File? srcDir(Bool checked := true) { throw UnsupportedErr() }

}

