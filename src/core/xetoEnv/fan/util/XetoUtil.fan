//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   25 Feb 2023  Brian Frank  Creation
//

using util
using xeto
using haystack::Etc
using haystack::Ref
using haystack::UnknownNameErr

**
** Utility functions
**
@Js
const class XetoUtil
{

//////////////////////////////////////////////////////////////////////////
// Naming
//////////////////////////////////////////////////////////////////////////

  ** Return if valid lib name
  static Bool isLibName(Str n)
  {
    libNameErr(n) == null
  }

  ** If the given lib is is not a valid name return an error message,
  ** otherwise if its valid return return null.
  static Str? libNameErr(Str n)
  {
    if (n.isEmpty) return "Lib name cannot be the empty string"
    if (!n[0].isLower) return "Lib name must start with lowercase letter"
    if (!n[-1].isLower && !n[-1].isDigit) return "Lib name must end with lowercase letter or digit"
    for (i := 0; i<n.size; ++i)
    {
      ch := n[i]
      prev := i == 0 ? 0 : n[i-1]
      if (ch.isUpper) return "Lib name must be all lowercase"
      if (prev == '.' && !ch.isLower) return "Lib dotted name sections must begin with lowercase letter"
      if (ch.isLower || ch.isDigit) continue
      if (ch == '_' || ch == '.')
      {
        if (prev.isLower || prev.isDigit) continue;
        return "Invalid adjacent chars at pos $i";
      }
      if (ch == ' ') return "Lib name cannot contain spaces"
      return "Invalid lib name char '$ch' 0x$ch.toHex"
    }
    return null
  }

  ** Return if valid spec name
  static Bool isSpecName(Str n)
  {
    if (n.isEmpty) return false
    ch := n[0]

    // _123
    if (ch == '_') return n.all |c, i| { i == 0 || c.isDigit }

    // Foo_Bar_123
    if (!ch.isAlpha) return false
    return n.all |c| { c.isAlphaNum || c == '_' }
  }

  ** Return if name is "_" + digits
  static Bool isAutoName(Str n)
  {
    if (n.size < 2 || n[0] != '_' || !n[1].isDigit) return false
    for (i:=2; i<n.size; ++i) if (!n[i].isDigit) return false
    return true
  }

  ** Convert "fooBarBaz" or "FooBarBaz" to "foo.bar.baz".
  static Str camelToDotted(Str name, Int dot := '.')
  {
    s := StrBuf(name.size + 4)
    name.each |char|
    {
      if (char.isUpper)
      {
        if (!s.isEmpty) s.addChar(dot)
        s.addChar(char.lower)
      }
      else
      {
        s.addChar(char)
      }
    }
    return s.toStr
  }

  ** Convert "fooBarBaz" or "FooBarBaz" to "foo-bar-baz".
  static Str camelToDashed(Str name)
  {
    camelToDotted(name, '-')
  }

  ** Convert "foo.bar.baz" to "fooBarBaz"
  static Str dottedToCamel(Str name, Int dot := '.')
  {
    s := StrBuf(name.size)
    capitalize := false
    name.each |char|
    {
      if (char == dot)
        capitalize = true
      else if (capitalize)
        { s.addChar(char.upper); capitalize = false }
      else
        s.addChar(char)
    }
    return s.toStr
  }

  ** Convert "foo-bar-baz" to "fooBarBaz"
  static Str dashedToCamel(Str name)
  {
    dottedToCamel(name, '-')
  }

  ** Convert "foo.bar::Baz" to simple name "Baz" or null if no "::"
  static Str? qnameToName(Str qname)
  {
    colon := qname.indexr(":")
    if (colon == null || colon < 2 || colon+1 >= qname.size || qname[colon-1] != ':') return null
    return qname[colon+1..-1]
  }

  ** Convert "foo.bar::Baz" to lib name "foo.bar" or null if no "::"
  static Str? qnameToLib(Str qname)
  {
    colon := qname.index(":")
    if (colon == null || colon < 1 || colon+2 >= qname.size || qname[colon+1] != ':') return null
    return qname[0..<colon]
  }

//////////////////////////////////////////////////////////////////////////
// Opts
//////////////////////////////////////////////////////////////////////////

  ** Get logging function from options
  static |XetoLogRec|? optLog(Dict? opts, Str name)
  {
    if (opts == null) return null
    x := opts.get(name, null)
    if (x == null) return null
    if (x is Unsafe) x = ((Unsafe)x).val
    if (x is Func) return x
    throw Err("Expecting |XetoLogRec| func for $name.toCode [$x.typeof]")
  }

//////////////////////////////////////////////////////////////////////////
// Meta
//////////////////////////////////////////////////////////////////////////

  ** Return if base is inherited
  static Bool isMetaInherited(CSpec base, Str name)
  {
    // we need to make this use reflection at some point
    if (name == "abstract") return false
    if (name == "sealed") return false
    if (name == "val") return !base.isEnum
    return true
  }

  static Void addOwnMeta(MEnv env, Str:Obj acc, Dict own)
  {
    if (own.isEmpty) return
    own.each |v, n|
    {
      if (v === env.none)
        acc.remove(n)
      else
        acc[n] = v
    }
  }

//////////////////////////////////////////////////////////////////////////
// Is-A
//////////////////////////////////////////////////////////////////////////

  ** Return if a is-a b
  static Bool isa(CSpec a, CSpec b, Bool isTop := true)
  {
    // check if a and b are the same
    if (a === b) return true

    // if A is "maybe" type, then it also matches None
    if (b.isNone && a.isMaybe && isTop) return true

    // if A is sys::And type, then check any of A.ofs is B
    if (a.isAnd)
    {
      ofs := a.cofs
      if (ofs != null && ofs.any |x| { x.cisa(b) }) return true
    }

    // if A is sys::Or type, then check all of A.ofs is B
    if (a.isOr)
    {
      ofs := a.cofs
      if (ofs != null && ofs.all |x| { x.cisa(b) }) return true
    }

    // if B is sys::Or type, then check if A is any of B.ofs
    if (b.isOr)
    {
      ofs := b.cofs
      if (ofs != null && ofs.any |x| { a.cisa(x) }) return true
    }

    // check a's base type
    if (a.cbase != null) return isa(a.cbase, b, false)

    return false
  }

//////////////////////////////////////////////////////////////////////////
// ChoiceOf
//////////////////////////////////////////////////////////////////////////

  ** Implementation of XetoEnv.choiceOf
  static Spec? choiceOf(MNamespace ns, Dict instance, Spec choice, Bool checked)
  {
    acc := Spec[,]
    ns.eachType |x|
    {
      if (!x.isa(choice)) return
      if (x.slots.isEmpty) return
      if (hasChoiceMarkers(instance, x)) acc.add(x)
    }

    // TODO: for now just compare on number of tags so that {hot, water}
    // trumps {water}. But that isn't correct because {naturalGas, hot, water}
    // would actually be incorrect with multiple matches
    if (acc.size > 1)
    {
      maxSize := 0
      acc.each |XetoSpec x| { maxSize = maxSize.max(x.m.slots.size) }
      acc = acc.findAll |XetoSpec x->Bool| { x.m.slots.size == maxSize }
    }

    // if exactly one
    if (acc.size == 1) return acc.first

    if (checked)
    {
      if (acc.isEmpty) throw Err("Choice not implemented by instance: $choice")
      else throw Err("Multiple choices implemented by instance: $choice $acc")
    }
    return null
  }

  ** Return if instance has all the given tags of the given choice
  static Bool hasChoiceMarkers(Dict instance, Spec choice)
  {
    r := choice.slots.eachWhile |slot|
    {
      instance.has(slot.name) ? null : "break"
    }
    return r == null
  }

//////////////////////////////////////////////////////////////////////////
// Derive
//////////////////////////////////////////////////////////////////////////

  ** Dervice a new spec from the given base, meta, and map
  static Spec derive(MNamespace ns, Str name, XetoSpec base, Dict meta, [Str:Spec]? slots)
  {
    // sanity checking
    if (!isSpecName(name)) throw ArgErr("Invalid spec name: $name")
    if (!base.isDict)
    {
      if (slots != null && !slots.isEmpty) throw ArgErr("Cannot add slots to non-dict type: $base")
    }

    spec := XetoSpec()
    m := MDerivedSpec(ns.env, null, ns.names.add(name), base, MNameDict(ns.names.dictDict(meta)), deriveSlots(ns, spec, slots), deriveFlags(base, meta))
    XetoSpec#m->setConst(spec, m)
    return spec
  }

  private static Int deriveFlags(XetoSpec base, Dict meta)
  {
    flags := base.m.flags
    if (meta.has("maybe")) flags = flags.or(MSpecFlags.maybe)
    return flags
  }

  private static MSlots deriveSlots(MNamespace ns, XetoSpec parent, [Str:Spec]? slotsMap)
  {
    if (slotsMap == null || slotsMap.isEmpty) return MSlots.empty

    derivedMap := slotsMap.map |XetoSpec base, Str name->XetoSpec|
    {
      XetoSpec(MDerivedSpec(ns.env, parent, ns.names.add(name), base, base.m.meta, base.m.slots, base.m.flags))
    }

    return MSlots(ns.names.dictMap(derivedMap))
  }

//////////////////////////////////////////////////////////////////////////
// Instantiate
//////////////////////////////////////////////////////////////////////////

  ** Instantiate default value of spec
  static Obj? instantiate(MNamespace ns, XetoSpec spec, Dict opts)
  {
    meta := spec.m.meta
    if (meta.has("abstract") && opts.missing("abstract")) throw Err("Spec is abstract: $spec.qname")

    if (spec.isNone) return null
    if (spec.isScalar || spec.has("val")) return instantiateScalar(ns, spec, meta)
    if (spec === ns.sys.dict) return Etc.dict0
    if (spec.isList) return Etc.list0

    isGraph := opts.has("graph")

    acc := Str:Obj[:]
    acc.ordered = true

    id := opts["id"]
    if (id == null && isGraph) id = Ref.gen
    if (id != null) acc["id"] = id

    acc["dis"] = XetoUtil.isAutoName(spec.name) ? spec.base.name : spec.name

    spec.slots.each |slot|
    {
      if (slot.isMaybe) return
      if (slot.isQuery) return
      if (slot.type === ns.sys.ref && slot.name != "enum") return // fill-in siteRef, equipRef, etc
      acc[slot.name] = instantiate(ns, slot, opts)
    }

    parent := opts["parent"] as Dict
    if (parent != null && parent["id"] is Ref)
    {
      // TODO: temp hack for equip/point common use case
      parentId := (Ref)parent["id"]
      if (parent.has("equip"))   acc["equipRef"] = parentId
      if (parent.has("site"))    acc["siteRef"]  = parentId
      if (parent.has("siteRef")) acc["siteRef"]  = parent["siteRef"]
    }

    dict := Etc.dictFromMap(acc)

    if (opts.has("graph"))
      return instantiateGraph(ns, spec, opts, dict)
    else
      return dict
  }

  private static Obj instantiateScalar(MNamespace ns, XetoSpec spec, Dict meta)
  {
    meta["val"] ?: ""
  }

  private static Dict[] instantiateGraph(MNamespace ns, XetoSpec spec, Dict opts, Dict dict)
  {
    opts = Etc.dictSet(opts, "parent", dict)
    graph := Dict[,]
    graph.add(dict)

    // recursively add constrained query children
    spec.slots.each |slot|
    {
      if (!slot.isQuery) return
      if (slot.slots.isEmpty) return
      slot.slots.each |x|
      {
        kids := instantiate(ns, x, opts)
        if (kids isnot List) return
        graph.addAll(kids)
      }
    }

    return graph
  }

//////////////////////////////////////////////////////////////////////////
// AST
//////////////////////////////////////////////////////////////////////////

  ** Generate AST dict tree for entire lib
  static Dict genAstLib(MEnv env, Lib lib, Bool isOwn, Dict opts)
  {
    acc := Str:Obj[:]
    acc.ordered = true

    acc["type"] = "sys::Lib"

    lib.meta.each |v, n|
    {
      if (n == "val" && v === env.marker) return
      acc[n] = genAstVal(env, v)
    }

    slots := Str:Obj[:]
    slots.ordered = true
    lib.specs.each |spec|
    {
      slots.add(spec.name, genAstSpec(env, spec, isOwn, opts))
    }
    acc.add("slots", env.dictMap(slots))

    return env.dictMap(acc)
  }

  ** Generate AST dict tree for spec
  static Dict genAstSpec(MEnv env, Spec spec, Bool isOwn, Dict opts)
  {
    acc := Str:Obj[:]
    acc.ordered = true

    if (spec.isType)
    {
      if (spec.base != null)  acc["base"] = spec.base.qname
    }
    else
    {
      acc["type"] = spec.type.qname
    }

    Dict meta := isOwn ? spec.metaOwn : spec.meta
    meta.each |v, n|
    {
      if (n == "val" && v === env.marker) return
      acc[n] = genAstVal(env, v)
    }

    if (opts.has("fileloc"))
      acc["fileloc"] = spec.loc.toStr

    slots := isOwn ? spec.slotsOwn : spec.slots
    if (!slots.isEmpty)
    {
      slotsAcc := Str:Obj[:]
      slotsAcc.ordered = true
      slots.each |slot|
      {
        noRecurse := slot.base?.type === slot.base && !slot.isType
        slotsAcc[slot.name] = genAstSpec(env, slot, isOwn || noRecurse, opts)
      }
      acc["slots"] = env.dictMap(slotsAcc)
    }

    return env.dictMap(acc)
  }

  private static Obj genAstVal(MEnv env, Obj val)
  {
    if (val is Spec) return val.toStr
    if (val is List)
    {
      return ((List)val).map |x| { genAstVal(env, x) }
    }
    if (val is Dict)
    {
      dict := (Dict)val
      if (dict.isEmpty) return dict
      acc := Str:Obj[:]
      acc.ordered = true
      isList := true // TODO
      ((Dict)val).each |v, n|
      {
        if (!XetoUtil.isAutoName(n)) isList = false
        acc[n] = genAstVal(env, v)
      }
      if (isList) return acc.vals // TODO: should already be a list!
      return env.dictMap(acc)
    }
    return val.toStr
  }
}

