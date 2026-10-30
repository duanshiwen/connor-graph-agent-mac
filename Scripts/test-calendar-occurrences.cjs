const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../Sources/ConnorGraphAppSupport/Resources/Calendar');
function engine() {
  const context = vm.createContext({module: {exports: {}}, connorZoneOffset: (id,y,m,d,h,min,s) => {
    const wall = Date.UTC(y,m-1,d,h,min,s); let guess = wall;
    const format = new Intl.DateTimeFormat('en-GB', {timeZone:id,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'});
    let offset;
    for (let i=0;i<4;i++) {
      const p = Object.fromEntries(format.formatToParts(guess).map(v => [v.type,v.value]));
      offset = (Date.UTC(+p.year,+p.month-1,+p.day,+p.hour,+p.minute,+p.second)-guess)/1000;
      guess = wall-offset*1000;
    }
    return offset;
  }});
  context.exports = context.module.exports;
  vm.runInContext(fs.readFileSync(path.join(root,'ical.es5.min.cjs'),'utf8'), context);
  context.exports = context.module.exports;
  vm.runInContext(fs.readFileSync(path.join(root,'occurrences.js'),'utf8'), context);
  return context;
}
const cal = body => 'BEGIN:VCALENDAR\nVERSION:2.0\n'+body+'\nEND:VCALENDAR';
const event = body => 'BEGIN:VEVENT\nUID:series\nSUMMARY:周会\n'+body+'\nEND:VEVENT';
const read = (context, body, from='2026-10-01',to='2027-01-01') => JSON.parse(context.connorOccurrences(body,Date.parse(from)/1000,Date.parse(to)/1000));
let count=0;
function check(name, test) {test();console.log('PASS '+name);count++;}
check('EXDATE, RDATE, moved and cancelled exceptions', () => {
  const text = cal(event('DTSTART:20261001T090000Z\nDTEND:20261001T100000Z\nRRULE:FREQ=DAILY;COUNT=5\nEXDATE:20261002T090000Z\nRDATE:20261008T090000Z')+'\n'+event('RECURRENCE-ID:20261003T090000Z\nDTSTART:20261003T140000Z\nDTEND:20261003T150000Z')+'\n'+event('RECURRENCE-ID:20261004T090000Z\nDTSTART:20261004T090000Z\nDTEND:20261004T100000Z\nSTATUS:CANCELLED'));
  const rows=read(engine(),text);
  assert.deepEqual(rows.map(r=>new Date(r.start*1000).toISOString()), ['2026-10-01T09:00:00.000Z','2026-10-03T14:00:00.000Z','2026-10-05T09:00:00.000Z','2026-10-08T09:00:00.000Z']);
  assert.equal(new Set(rows.map(r=>r.recurrenceID)).size,4);
});
check('DST keeps wall time', () => {
  const rows=read(engine(),cal(event('DTSTART;TZID=America/New_York:20261031T090000\nDTEND;TZID=America/New_York:20261031T100000\nRRULE:FREQ=DAILY;COUNT=3')));
  assert.deepEqual(rows.map(r=>new Date(r.start*1000).getUTCHours()),[13,14,14]);
});
check('Quoted CN and all participants', () => {
  const rows=read(engine(),cal(event('DTSTART:20261001T090000Z\nDTEND:20261001T100000Z\nORGANIZER;CN="Connor: Team":mailto:owner@example.com\nATTENDEE;CN="Alice; Zhang":mailto:alice@example.com\nATTENDEE;CN=Bob:mailto:bob@example.com')));
  assert.equal(rows[0].attendees.length,2); assert.equal(rows[0].attendees[0].name,'Alice; Zhang'); assert.equal(rows[0].organizer.email,'owner@example.com');
});
check('Ordinal monthly recurrence', () => {
  const rows=read(engine(),cal(event('DTSTART:20261001T090000Z\nDTEND:20261001T100000Z\nRRULE:FREQ=MONTHLY;COUNT=3;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=1')));
  assert.deepEqual(rows.map(r=>new Date(r.start*1000).getUTCDate()),[1,2,1]);
});
check('All-day defaults and repeats', () => {
  const rows=read(engine(),cal(event('DTSTART;VALUE=DATE:20261001\nRRULE:FREQ=DAILY;COUNT=2')));
  assert.equal(rows.length,2); assert.ok(rows.every(r=>r.allDay && r.end-r.start===86400));
});
check('VTIMEZONE and merged series preserve EXDATE', () => {
  const c=engine(), zone='BEGIN:VTIMEZONE\nTZID:Custom/Office\nBEGIN:STANDARD\nDTSTART:19700101T000000\nTZOFFSETFROM:+0530\nTZOFFSETTO:+0530\nEND:STANDARD\nEND:VTIMEZONE\n';
  const text=cal(zone+event('DTSTART;TZID=Custom/Office:20261001T090000\nDTEND;TZID=Custom/Office:20261001T100000\nRRULE:FREQ=DAILY;COUNT=3\nEXDATE;TZID=Custom/Office:20261002T090000'));
  assert.equal(new Date(read(c,text)[0].start*1000).toISOString(),'2026-10-01T03:30:00.000Z');
  const replacement=cal(event('DTSTART:20261001T033000Z\nDTEND:20261001T043000Z\nRRULE:FREQ=DAILY;COUNT=3').replace('SUMMARY:周会','SUMMARY:改名'));
  const merged=c.connorMergeSeries(text,replacement); assert.ok(merged.includes('EXDATE')); assert.equal(read(c,merged).length,2);
});
check('Future moved exception from outside evaluated interval', () => {
  const text=cal(event('DTSTART:20261101T090000Z\nDTEND:20261101T100000Z\nRRULE:FREQ=DAILY;COUNT=2')+'\n'+event('RECURRENCE-ID:20261102T090000Z\nDTSTART:20261003T090000Z\nDTEND:20261003T100000Z'));
  assert.equal(read(engine(),text,'2026-10-01','2026-10-10').length,1);
});
check('Malformed snapshot rejected', () => assert.throws(()=>read(engine(),'BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:bad')));
check('Range exceptions change only this and later dates', () => {
  const text=cal(event('DTSTART:20261001T090000Z\nDTEND:20261001T100000Z\nRRULE:FREQ=DAILY;COUNT=5')+'\n'+event('RECURRENCE-ID;RANGE=THISANDFUTURE:20261003T090000Z\nDTSTART:20261003T140000Z\nDTEND:20261003T150000Z').replace('SUMMARY:周会','SUMMARY:改名'));
  const rows=read(engine(),text);
  assert.equal(rows.length,5); assert.deepEqual(rows.map(r=>new Date(r.start*1000).getUTCHours()),[9,9,14,14,14]);
});
console.log(`${count} calendar engine checks passed; Swift/JavaScriptCore integration requires macOS.`);
