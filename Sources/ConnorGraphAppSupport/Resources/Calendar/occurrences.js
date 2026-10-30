/* Connor bridge for the unmodified MPL-2.0 ical.js distribution beside this file. */
var ICAL = module.exports;
var originalZoneGet = ICAL.TimezoneService.get;
ICAL.TimezoneService.get = function (id) {
  var known = originalZoneGet.call(ICAL.TimezoneService, id);
  if (known || !id) return known;
  var zone = new ICAL.Timezone({tzid: id});
  zone.utcOffset = function (time) {
    var seconds = connorZoneOffset(id, time.year, time.month, time.day, time.hour, time.minute, time.second);
    if (!isFinite(seconds)) throw new Error('Unknown calendar timezone: ' + id);
    return seconds;
  };
  return zone;
};
function connorReadCalendar(text, lower, upper, expand) {
  var root = new ICAL.Component(ICAL.parse(text)), output = [], work = 0;
  root.getAllSubcomponents('vtimezone').forEach(function (c) {
    var id = c.getFirstPropertyValue('tzid');
    if (id) ICAL.TimezoneService.register(id, new ICAL.Timezone(c));
  });
  var components = root.getAllSubcomponents('vevent'), byUID = Object.create(null);
  components.forEach(function (c) {
    var uid = c.getFirstPropertyValue('uid');
    if (!uid) throw new Error('Calendar event has no UID');
    (byUID[uid] || (byUID[uid] = [])).push(c);
  });
  function epoch(time) {
    // DATE values are calendar dates, independent of the computer's timezone.
    if (time.isDate) return Date.UTC(time.year, time.month - 1, time.day) / 1000;
    if (time.zone === ICAL.Timezone.localTimezone) return new Date(time.year, time.month - 1, time.day, time.hour, time.minute, time.second).getTime() / 1000;
    return time.toUnixTime();
  }
  function person(p) {
    return {name:p.getParameter('cn') || null, email:String(p.getFirstValue() || '').replace(/^mailto:/i, ''), role:p.getParameter('role') || null, status:p.getParameter('partstat') || null};
  }
  function append(event, start, end, recurrenceID, master) {
    var c = event.component;
    if (String(c.getFirstPropertyValue('status') || '').toUpperCase() === 'CANCELLED') return;
    var a = epoch(start), b = epoch(end);
    if (a >= upper || b < lower) return;
    if (output.length >= 10000) throw new Error('Too many calendar occurrences; narrow the sync window');
    var organizer = c.getFirstProperty('organizer'), modified = c.getFirstPropertyValue('last-modified');
    output.push({uid:event.uid, summary:event.summary || '未命名日程', start:a, end:b, allDay:start.isDate,
      zone:start.zone && start.zone.tzid !== 'floating' ? start.zone.tzid : null,
      location:event.location || null, notes:event.description || null, url:c.getFirstPropertyValue('url') || null,
      status:c.getFirstPropertyValue('status') || null, rule:master.component.getFirstPropertyValue('rrule') ? String(master.component.getFirstPropertyValue('rrule')) : null,
      modified:modified ? epoch(modified) : null, recurrenceID:recurrenceID, organizer:organizer ? person(organizer) : null,
      attendees:c.getAllProperties('attendee').map(person)});
  }
  Object.keys(byUID).forEach(function (uid) {
    var list = byUID[uid], base = list.filter(function (c) {return !c.hasProperty('recurrence-id');});
    if (!base.length) base = list;
    base.forEach(function (component) {
      var event = new ICAL.Event(component);
      if (!component.hasProperty('dtstart')) throw new Error('Calendar event has no DTSTART');
      if (!expand || !event.isRecurring()) {append(event,event.startDate,event.endDate,component.hasProperty('recurrence-id') ? String(component.getFirstPropertyValue('recurrence-id')) : null,event); return;}
      list.forEach(function (c) {if(c !== component && c.hasProperty('recurrence-id')) event.relateException(new ICAL.Event(c));});
      var iterator = event.iterator(), occurrence;
      while ((occurrence = iterator.next())) {
        if (++work > 500000) throw new Error('Calendar recurrence evaluation limit exceeded');
        if (epoch(occurrence) >= upper) break;
        var detail = event.getOccurrenceDetails(occurrence);
        append(detail.item,detail.startDate,detail.endDate,occurrence.toString(),event);
      }
      // Moved exceptions can fall within the window while their original occurrence is outside it.
      list.forEach(function (c) {
        if (!c.hasProperty('recurrence-id') || String(c.getFirstPropertyValue('status') || '').toUpperCase() === 'CANCELLED') return;
        var exception = new ICAL.Event(c), rid = String(c.getFirstPropertyValue('recurrence-id'));
        if (!output.some(function (row) {return row.uid === uid && row.recurrenceID === rid;})) append(exception,exception.startDate,exception.endDate,rid,event);
      });
    });
  });
  return JSON.stringify(output.sort(function (a,b) {return a.start - b.start;}));
}
function connorOccurrences(text, lower, upper) {return connorReadCalendar(text,lower,upper,true);}
function connorSeries(text, lower, upper) {return connorReadCalendar(text,lower,upper,false);}
function connorMergeSeries(original, replacement, clearRecurrence) {
  var root = new ICAL.Component(ICAL.parse(original));
  root.getAllSubcomponents('vtimezone').forEach(function(c) {ICAL.TimezoneService.register(c.getFirstPropertyValue('tzid'),new ICAL.Timezone(c));});
  var incoming = new ICAL.Component(ICAL.parse(replacement)).getFirstSubcomponent('vevent');
  var uid = incoming.getFirstPropertyValue('uid');
  var target = root.getAllSubcomponents('vevent').filter(function(c) {return c.getFirstPropertyValue('uid') === uid && !c.hasProperty('recurrence-id');})[0];
  if (!target) throw new Error('Calendar series master was not found');
  ['summary','dtstart','dtend','location','description','url','rrule'].forEach(function(name) {
    if ((name === 'dtstart' || name === 'dtend') && target.hasProperty(name) && incoming.hasProperty(name)) {
      var before = target.getFirstPropertyValue(name), after = incoming.getFirstPropertyValue(name);
      if (before.isDate === after.isDate && before.toUnixTime() === after.toUnixTime()) return;
    }
    target.removeAllProperties(name);
    incoming.getAllProperties(name).forEach(function(p) {target.addProperty(new ICAL.Property(JSON.parse(JSON.stringify(p.toJSON()))));});
  });
  target.removeAllProperties('duration');
  if (clearRecurrence) {
    target.removeAllProperties('rdate'); target.removeAllProperties('exdate');
    root.getAllSubcomponents('vevent').forEach(function(c) {if(c.getFirstPropertyValue('uid') === uid && c.hasProperty('recurrence-id')) root.removeSubcomponent(c);});
  }
  return root.toString();
}
