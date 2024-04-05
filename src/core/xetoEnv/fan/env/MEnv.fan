//
// Copyright (c) 2023, Brian Frank
// Licensed under the Academic Free License version 3.0
//
// History:
//   16 Jan 2023  Brian Frank  Creation
//

using concurrent
using util
using xeto
using haystack::Etc
using haystack::Marker
using haystack::NA
using haystack::Remove
using haystack::Grid
using haystack::Symbol
using haystack::UnknownSpecErr

**
** XetoEnv implementation
**
@Js
abstract const class MEnv : XetoEnv
{
  new make(NameTable names, MRegistry registry, |This|? f)
  {
    this.names       = names
    this.none        = Remove.val
    this.marker      = Marker.val
    this.na          = NA.val
    this.list0       = Obj?[,]
    this.dict0       = Etc.dict0
    this.specSpecRef = haystack::Ref("sys::Spec", null)
    this.libSpecRef  = haystack::Ref("sys::Lib", null)
    this.registryRef = registry
    if (f != null) f(this)
    this.sysLib      = registry.loadSync("sys")
    this.sys         = MSys(sysLib)
    this.dictSpec    = sys.dict
  }

  const override Lib sysLib

  const MSys sys

  override const NameTable names

  const MFactories factories := MFactories()

  override MRegistry registry() { registryRef }

  const MRegistry registryRef

  internal const NilContext nilContext := NilContext()

  const override Obj marker

  const override Obj none

  const override Obj na

  const Obj?[] list0

  const Ref specSpecRef

  const Ref libSpecRef

  const override Spec dictSpec

  const override Dict dict0

  override Dict dict1(Str n, Obj v) { Etc.dict1(n, v) }

  override Dict dict2(Str n0, Obj v0, Str n1, Obj v1) {  Etc.dict2(n0, v0, n1, v1) }

  override Dict dict3(Str n0, Obj v0, Str n1, Obj v1, Str n2, Obj v2) {  Etc.dict3(n0, v0, n1, v1, n2, v2)  }

  override Dict dict4(Str n0, Obj v0, Str n1, Obj v1, Str n2, Obj v2, Str n3, Obj v3) { Etc.dict4(n0, v0, n1, v1, n2, v2, n3, v3) }

  override Dict dict5(Str n0, Obj v0, Str n1, Obj v1, Str n2, Obj v2, Str n3, Obj v3, Str n4, Obj v4) { Etc.dict5(n0, v0, n1, v1, n2, v2, n3, v3, n4, v4) }

  override Dict dict6(Str n0, Obj v0, Str n1, Obj v1, Str n2, Obj v2, Str n3, Obj v3, Str n4, Obj v4, Str n5, Obj v5) { Etc.dict6(n0, v0, n1, v1, n2, v2, n3, v3, n4, v4, n5, v5) }

  override Dict dictMap(Str:Obj map) { Etc.dictFromMap(map) }

  override Dict dict(Obj? val)
  {
    if (val == null) return dict0
    if (val is Dict) return val
    map := val as Str:Obj ?: throw ArgErr("Unsupported dict arg: $val.typeof")
    return dictMap(map)
  }

  override Ref ref(Str id, Str? dis := null) { haystack::Ref.make(id, dis) }

  override Spec? specOf(Obj? val, Bool checked := true)
  {
    if (val == null) return sys.none

    // dict handling
    dict := val as Dict
    if (dict != null)
    {
      specRef := dict["spec"] as Ref
      if (specRef == null) return dictSpec
      return spec(specRef.id, checked)
    }

    // look in Fantom class hiearchy
    type := val as Type ?: val.typeof
    for (Type? p := type; p != null; p = p.base)
    {
      spec := factories.typeToSpec(p)
      if (spec != null) return spec
      spec = p.mixins.eachWhile |m| { factories.typeToSpec(m) }
      if (spec != null) return spec
    }

    // fallbacks
    if (val is List) return sys.list
    if (type.fits(Grid#)) return lib("ph").type("Grid")

    // cannot map to spec
    if (checked) throw UnknownSpecErr("No spec mapped for '$type'")
    return null
  }

  override XetoLib? lib(Str name, Bool checked := true)
  {
    registry.loadSync(name, checked)
  }

  override Void libAsync(Str name, |Err?, Lib?| f)
  {
    registry.loadAsync(name, f)
  }

  override Void libAsyncList(Str[] names, |Err?| f)
  {
    registry.loadAsyncList(names, f)
  }

  override XetoType? type(Str qname, Bool checked := true)
  {
    colon := qname.index("::") ?: throw ArgErr("Invalid qname: $qname")
    libName := qname[0..<colon]
    typeName := qname[colon+2..-1]
    type := lib(libName, false)?.type(typeName, false)
    if (type != null) return type
    if (checked) throw UnknownSpecErr("Unknown data type: $qname")
    return null
  }

  override XetoSpec? spec(Str qname, Bool checked := true)
  {
    colon := qname.index("::") ?: throw ArgErr("Invalid qname: $qname")

    libName := qname[0..<colon]
    names := qname[colon+2..-1].split('.', false)

    spec := lib(libName, false)?.spec(names.first, false)
    for (i:=1; spec != null && i<names.size; ++i)
      spec = spec.slot(names[i], false)

    if (spec != null) return spec
    if (checked) throw UnknownSpecErr(qname)
    return null
  }

  override Dict? instance(Str qname, Bool checked := true)
  {
    colon := qname.index("::") ?: throw ArgErr("Invalid qname: $qname")

    libName := qname[0..<colon]
    name := qname[colon+2..-1]

    instance := lib(libName, false)?.instance(name, false)

    if (instance != null) return instance
    if (checked) throw haystack::UnknownRecErr(qname)
    return null
  }

  override Spec derive(Str name, Spec base, Dict meta, [Str:Spec]? slots := null)
  {
    XetoUtil.derive(this, name, base, meta, slots)
  }

  override Obj? instantiate(Spec spec, Dict? opts := null)
  {
    XetoUtil.instantiate(this, spec, opts ?: dict0)
  }

  override Dict[] compileDicts(Str src, Dict? opts := null)
  {
    val := compileData(src, opts)
    if (val is List) return ((List)val).map |x->Dict| { x as Dict ?: throw IOErr("Expecting Xeto list of dicts, not ${x?.typeof}") }
    if (val is Dict) return Dict[val]
    throw IOErr("Expecting Xeto dict data, not ${val?.typeof}")
  }

  override Void writeData(OutStream out, Obj val, Dict? opts := null)
  {
    Printer(this, out, opts ?: dict0).xetoTop(val)
  }

  override Bool specFits(Spec a, Spec b, Dict? opts := null)
  {
    if (opts == null) opts = dict0
    explain := XetoUtil.optLog(opts, "explain")
    cx := nilContext
    if (explain == null)
      return Fitter(this, cx, opts).specFits(a, b)
    else
      return ExplainFitter(this, cx, opts, explain).specFits(a, b)
  }

  override Bool fits(XetoContext cx, Obj? val, Spec spec, Dict? opts := null)
  {
    if (opts == null) opts = dict0
    explain := XetoUtil.optLog(opts, "explain")
    if (explain == null)
      return Fitter(this, cx, opts).valFits(val, spec)
    else
      return ExplainFitter(this, cx, opts, explain).valFits(val, spec)
  }

  override Spec? choiceOf(Dict instance, Spec choice, Bool checked := true)
  {
    XetoUtil.choiceOf(this, instance, choice, checked)
  }

  override Obj? queryWhile(XetoContext cx, Dict subject, Spec query, Dict? opts, |Dict->Obj?| f)
  {
    // TODO: redesign to use eachWhile
    acc := Query(this, cx, opts).query(subject, query)
    return acc.eachWhile(f)
  }

  override Dict genAst(Obj libOrSpec, Dict? opts := null)
  {
    if (opts == null) opts = dict0
    isOwn := opts.has("own")
    if (libOrSpec is Lib)
      return XetoUtil.genAstLib(this, libOrSpec, isOwn, opts)
    else
      return XetoUtil.genAstSpec(this, libOrSpec, isOwn, opts)
  }

  override Void print(Obj? val, OutStream out := Env.cur.out, Dict? opts := null)
  {
    Printer(this, out, opts ?: dict0).print(val)
  }

}

**************************************************************************
** NilContext
**************************************************************************

@Js
internal const class NilContext : XetoContext
{
  override Dict? xetoReadById(Obj id) { null }
  override Obj? xetoReadAllEachWhile(Str filter, |Dict->Obj?| f) { null }
  override Bool xetoIsSpec(Str spec, Dict rec) { false }
}

