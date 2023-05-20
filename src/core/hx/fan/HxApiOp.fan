//
// Copyright (c) 2021, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   1 Jun 2021  Brian Frank  Creation
//

using concurrent
using web
using haystack
using axon
using folio

**
** Base class for HTTP API operation processing
**
abstract class HxApiOp
{
  ** Subclasses must declare public no-arg constructor
  new make()
  {
    this.spiRef = Actor.locals["hxApiOp.spi"] as HxApiOpSpi ?: throw Err("Invalid make context")
  }

  ** Programmatic name of the op
  Str name() { spi.name }

  ** Op definition
  Def def() { spi.def }

  ** Process an HTTP service call to this op
  virtual Void onService(WebReq req, WebRes res, HxContext cx)
  {
    // parse request grid; if readReq returns null
    // then an error has already been returned
    reqGrid := spi.readReq(this, req, res)
    if (reqGrid == null) return

    // subclass hook
    resGrid := onRequest(reqGrid, cx)

    // respond with resulting grid
    spi.writeRes(this, req, res, resGrid)
  }

  ** Process parsed request.  Default implentation
  ** attempts to eval an Axon function of the same name.
  abstract Grid onRequest(Grid req, HxContext cx)

  ** Return if this operation can be called with GET method.
  @NoDoc virtual Bool isGetAllowed()
  {
    def.has("noSideEffects")
  }

  ** Service provider interface
  @NoDoc virtual HxApiOpSpi spi() { spiRef }
  @NoDoc const HxApiOpSpi spiRef
}

**************************************************************************
** HxApiOpSpi
**************************************************************************

**
** HxApiOp service provider interface
**
@NoDoc
const mixin HxApiOpSpi
{
  abstract Str name()
  abstract Def def()
  abstract Grid? readReq(HxApiOp op, WebReq req, WebRes res)
  abstract Void writeRes(HxApiOp op, WebReq req, WebRes res, Grid result)
}

**************************************************************************
** HxAboutOp
**************************************************************************

internal class HxAboutOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    Etc.makeDictGrid(null, HxCoreFuncs.about)
  }
}

**************************************************************************
** HxCloseOp
**************************************************************************

internal class HxCloseOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    cx.rt.user.closeSession(cx.session)
    return Etc.emptyGrid
  }
}

**************************************************************************
** HxDefsOp
**************************************************************************

internal class HxDefsOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    opts := req.first as Dict ?: Etc.emptyDict
    limit := (opts["limit"] as Number)?.toInt ?: Int.maxVal
    filter := Filter.fromStr(opts["filter"] as Str ?: "", false)
    acc := Def[,]
    incomplete := false
    eachDef(cx) |def|
    {
      if (filter != null && !filter.matches(def, cx)) return
      if (acc.size >= limit) { incomplete = true; return }
      acc.add(def)
    }
    meta := incomplete ? Etc.makeDict2("incomplete", Marker.val, "limit", Number(limit)) : Etc.emptyDict
    return Etc.makeDictsGrid(meta, acc)
  }

  virtual Void eachDef(HxContext cx, |Def| f) { cx.ns.eachDef(f) }
}

**************************************************************************
** HxFiletypesOp
**************************************************************************

internal class HxFiletypesOp : HxDefsOp
{
  override Void eachDef(HxContext cx, |Def| f) { cx.ns.filetypes.each(f) }
}

**************************************************************************
** HxLibsOp
**************************************************************************

internal class HxLibsOp : HxDefsOp
{
  override Void eachDef(HxContext cx, |Def| f) { cx.ns.libsList.each(f) }
}

**************************************************************************
** HxOpsOp
**************************************************************************

internal class HxOpsOp : HxDefsOp
{
  override Void eachDef(HxContext cx, |Def| f) { cx.ns.feature("op").eachDef(f) }
}

**************************************************************************
** HxReadOp
**************************************************************************

internal class HxReadOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    if (req.isEmpty) throw Err("Request grid is empty")

    if (req.has("filter"))
    {
      reqRow := req.first
      filter := Filter.fromStr(reqRow->filter)
      opts   := reqRow
      return cx.db.readAll(filter, opts)
    }

    if (req.has("id"))
    {
      return cx.db.readByIds(req.ids, false)
    }

    throw Err("Request grid missing id or filter col")
  }
}

**************************************************************************
** HxEvalOp
**************************************************************************

internal class HxEvalOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    if (req.isEmpty) throw Err("Request grid is empty")
    expr := (Str)req.first->expr
    return Etc.toGrid(cx.evalOrReadAll(expr))
  }
}

**************************************************************************
** HxCommitOp
**************************************************************************

internal class HxCommitOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    if (!cx.user.isAdmin) throw PermissionErr("Missing 'admin' permission: commit")
    mode := req.meta->commit
    switch (mode)
    {
      case "add":    return onAdd(req, cx)
      case "update": return onUpdate(req, cx)
      case "remove": return onRemove(req, cx)
      default:       throw ArgErr("Unknown commit mode: $mode")
    }
  }

  private Grid onAdd(Grid req, HxContext cx)
  {
    diffs := Diff[,]
    req.each |row|
    {
      changes := Str:Obj?[:]
      Ref? id := null
      row.each |v, n|
      {
        if (n == "id") { id = v; return }
        changes.add(n, v)
      }
      diffs.add(Diff.makeAdd(changes, id ?: Ref.gen))
    }
    newRecs := cx.db.commitAll(diffs).map |d->Dict| { d.newRec }
    return Etc.makeDictsGrid(null, newRecs)
  }

  private Grid onUpdate(Grid req, HxContext cx)
  {
    flags := 0
    if (req.meta.has("force"))     flags = flags.or(Diff.force)
    if (req.meta.has("transient")) flags = flags.or(Diff.transient)

    diffs := Diff[,]
    req.each |row|
    {
      old := Etc.makeDict(["id":row.id, "mod":row->mod])
      changes := Str:Obj?[:]
      row.each |v, n|
      {
        if (n == "id" || n == "mod") return
        changes.add(n, v)
      }
      diffs.add(Diff(old, changes, flags))
    }
    newRecs := cx.db.commitAll(diffs).map |d->Dict| { d.newRec }
    return Etc.makeDictsGrid(null, newRecs)
  }

  private Grid onRemove(Grid req, HxContext cx)
  {
    flags := Diff.remove
    if (req.meta.has("force")) flags = flags.or(Diff.force)

    diffs := Diff[,]
    req.each |row| { diffs.add(Diff(row, null, flags)) }
    cx.db.commitAll(diffs)
    return Etc.makeEmptyGrid
  }
}

**************************************************************************
** HxNavOp
**************************************************************************

internal class HxNavOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // check if we have nav function defined and if so use it
    func := cx.findTop("nav", false)
    if (func != null) return func.call(cx, [req])

    // use simple site/equip/point navigation
    navId := req.first?.get("navId") as Ref
    if (navId == null)
    {
      // if querying root, try sites first
      sites := cx.db.readAllList(Filter("site"))
      if (!sites.isEmpty) return respond(sites)

      // if no sites, then try equip
      equips := cx.db.readAllList(Filter("equip"))
      if (!equips.isEmpty) return respond(equips)

      // if no equip, then return points
      return respond(cx.db.readAllList(Filter("point")))
    }

    // try to navigate site/equip or equip/point
    rec := cx.db.readById(navId)
    if (rec.has("site"))
      return respond(cx.db.readAllList(Filter("equip and siteRef==$rec.id.toCode")))
    else if (rec.has("equip"))
      return respond(cx.db.readAllList(Filter("point and equipRef==$rec.id.toCode")))
    else
      return Etc.emptyGrid
  }

  private Grid respond(Dict[] recs)
  {
    if (recs.isEmpty) return Etc.emptyGrid
    recs = recs.map |rec->Dict|
    {
      if (rec.has("point")) return rec
      return Etc.dictSet(rec, "navId", rec.id)
    }
    Etc.sortDictsByDis(recs)
    return Etc.makeDictsGrid(null, recs)
  }
}

**************************************************************************
** HxWatchSubOp
**************************************************************************

@NoDoc class HxWatchSubOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // lookup or create watch
    watchId := req.meta["watchId"] as Str
    watch := watchId == null ?
             cx.rt.watch.open(req.meta->watchDis) :
             cx.rt.watch.get(watchId)

    // map rows to Refs
    ids := req.ids

    // set lease if specified
    lease := req.meta["lease"] as Number
    if (lease != null) watch.lease = lease.toDuration

    // add the ids
    watch.addAll(ids)

    // return recs - must return row for each requested id (so don't use Etc)
    resMeta := Etc.makeDict2("watchId", watch.id, "lease", Number.makeDuration(watch.lease, null))
    recs := cx.rt.db.readByIdsList(ids, false)
    colNames := Etc.dictsNames(recs)
    gb := GridBuilder()
    gb.setMeta(resMeta)
    if (colNames.isEmpty)
    {
      // this is what happens when we have zero matches from request
      gb.addCol("id")
      recs.each { gb.addRow1(null) }
    }
    else
    {
      // at least one rec was found
      colNames.each |colName| { gb.addCol(colName) }
      gb.addDictRows(recs)
    }
    return gb.toGrid
  }
}

**************************************************************************
** HxWatchUnsubOp
**************************************************************************

@NoDoc class HxWatchUnsubOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // parse reqeust
    watchId := req.meta["watchId"] as Str ?: throw Err("Missing meta.watchId")
    close := req.meta.has("close")

    // lookup watch
    watch := cx.rt.watch.get(watchId, false)
    if (watch == null) return Etc.emptyGrid

    // if no rows then close, otherwise remove
    if (close)
      watch.close
    else
      watch.removeGrid(req)
    return Etc.emptyGrid
  }
}

**************************************************************************
** HxWatchPollOp
**************************************************************************

internal class HxWatchPollOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // parse reqeust
    watchId := req.meta["watchId"] as Str ?: throw Err("Missing meta.watchId")
    refresh := req.meta.has("refresh")
    curValSub := req.meta.has("curValSub")

    // poll as refresh or cov
    watch := cx.rt.watch.get(watchId)
    recs := refresh ? watch.poll(Duration.defVal) : watch.poll
    resMeta := Etc.makeDict1("watchId", watchId)
    if (curValSub)
    {
      return GridBuilder()
        .setMeta(resMeta)
        .addCol("id")
        .addCol("curVal")
        .addCol("curStatus")
        .addDictRows(recs).toGrid
    }
    else
    {
      return Etc.makeDictsGrid(resMeta, recs)
    }
  }
}

**************************************************************************
** HxHisReadOp
**************************************************************************

internal class HxHisReadOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // parse request
    if (req.isEmpty) throw Err("Request grid is empty")
    reqRow := req.first
    rec := cx.db.readById(reqRow.id)
    tz := FolioUtil.hisTz(rec)
    span := parseRange(tz, reqRow->range)

    // convert timezones if needed so that clients are
    // free to request/convert the timezone as they see fit
    span = span.toTimeZone(tz)

    // query items
    meta := [
      "id": rec.id,
      "hisStart": span.start,
      "hisEnd": span.end
    ]

    gb := GridBuilder().setMeta(meta).addCol("ts").addCol("val")
    cx.rt.his.read(rec, span, req.meta) |item|
    {
      if (item.ts < span.start) return
      if (item.ts >= span.end) return
      gb.addRow2(item.ts, item.val)
    }
    return gb.toGrid
  }

  static Span? parseRange(TimeZone tz, Str q)
  {
    try
    {
      if (q == "today")     return DateSpan.today.toSpan(tz)
      if (q == "yesterday") return DateSpan.yesterday.toSpan(tz)

      Obj? start := null
      Obj? end := null
      comma := q.index(",")
      if (comma == null)
      {
        start = ZincReader(q.in).readVal
      }
      else
      {
        start = ZincReader(q[0..<comma].trim.in).readVal
        end   = ZincReader(q[comma+1..-1].trim.in).readVal
      }

      if (start is Date)
      {
        if (end == null) return DateSpan.make(start).toSpan(tz)
        if (end is Date) return DateSpan.make(start, end).toSpan(tz)
      }
      else if (start is DateTime)
      {
        if (end == null) return Span.makeAbs(start, DateTime.now.toTimeZone(((DateTime)start).tz))
        if (end is DateTime) return Span.makeAbs(start, end)
      }
      return null
    }
    catch (Err e) throw ParseErr("Invalid history range: $q", e)
  }
}

//////////////////////////////////////////////////////////////////////////
// HisWrite
//////////////////////////////////////////////////////////////////////////

internal class HxHisWriteOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // check security
    cx.checkAdmin("hisWrite op")

    // check for single vs batch
    if (req.meta.has("id"))
      onSingle(req, cx)
    else
      onBatch(req, cx)

    return Etc.emptyGrid
  }

  private Void onSingle(Grid req, HxContext cx)
  {
    write(req, cx, req.meta.id, req.col("ts"), req.col("val"))
  }

  private Void onBatch(Grid req, HxContext cx)
  {
    tsCol := req.cols[0]
    if (tsCol.name != "ts") throw Err("First col must be named 'ts', not '$tsCol.name'")

    req.cols.eachRange(1..-1) |valCol|
    {
      id := valCol.meta["id"] as Ref ?: throw Err("Col missing id tag: $valCol.name")
      write(req, cx, id, tsCol, valCol)
    }
  }

  private Void write(Grid req, HxContext cx, Ref id, Col tsCol, Col valCol)
  {
    // lookup history record
    rec := cx.db.readById(id)

    // map ts/val rows into HisItem list
    items := HisItem[,]
    items.capacity = req.size
    req.each |row|
    {
      tsRaw := row.val(tsCol)
      ts := tsRaw as DateTime ?: throw Err("Timestamp value is not DateTime: $tsRaw [${tsRaw?.typeof}]")
      val := row.val(valCol)
      if (val == null) return
      items.add(HisItem(ts, val))
    }

    // perform write
    opts := req.meta
    cx.rt.his.write(rec, items, opts)
  }
}

**************************************************************************
** HxPointWriteOp
**************************************************************************

internal class HxPointWriteOp : HxApiOp
{
  override Grid onRequest(Grid req, HxContext cx)
  {
    // parse request
    if (req.size != 1) throw Err("Request grid must have 1 row")
    reqRow := req.first
    rec := cx.db.readById(reqRow.id)

    // if reading level will be null
    level := reqRow["level"] as Number
    if (level == null) return cx.rt.pointWrite.array(rec)

    // handlw write
    cx.checkAdmin("pointWrite op")
    val := reqRow["val"]
    who := reqRow["who"]?.toStr ?: cx.user.dis
    dur := reqRow["duration"] as Number

    who = "Haystack.pointWrite | $who"

    // if have timed override
    if (val != null && level.toInt == 8 && dur != null)
      val = Etc.makeDict2("val", val, "duration", dur.toDuration)

    cx.rt.pointWrite.write(rec, val, level.toInt, who).get(30sec)
    return Etc.makeEmptyGrid(Etc.makeDict1("ok", Marker.val))
  }
}


