const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

function minutes(value) {
  if (typeof value !== 'string' || !/^\d{1,2}:\d{2}$/.test(value)) return null;
  const [h, m] = value.split(':').map(Number);
  return h < 24 && m < 60 ? h * 60 + m : null;
}

function intervals(roster) {
  if (!roster || typeof roster !== 'object' || !roster.days ||
      !['Europe/Brussels'].includes(roster.timezone)) return null;
  const spans = [];
  for (let day = 0; day < 7; day++) {
    const rows = roster.days[days[day]];
    if (!Array.isArray(rows)) return null;
    for (const row of rows) {
      const start = minutes(row?.start);
      const end = minutes(row?.end);
      if (start === null || end === null || start === end) return null;
      const from = day * 1440 + start;
      const to = day * 1440 + end + (end < start ? 1440 : 0);
      spans.push([from, to]);
      // The Sunday night tail must also collide with Monday morning.
      if (to > 7 * 1440) spans.push([from - 7 * 1440, to - 7 * 1440]);
    }
  }
  return spans;
}

// Conservative: a missing/unknown schedule or date exception requires manual
// review. It must never be interpreted as an empty, conflict-free schedule.
export function checkSharedVehicleRoster(candidate, others) {
  if (Array.isArray(candidate?.roster_exceptions) && candidate.roster_exceptions.length) {
    return { ok: false, reason: 'candidate_roster_exceptions' };
  }
  const requested = intervals(candidate?.weekly_roster);
  if (!requested || requested.length === 0) return { ok: false, reason: 'candidate_roster_unknown' };
  for (const other of others) {
    if (Array.isArray(other?.roster_exceptions) && other.roster_exceptions.length) {
      return { ok: false, reason: 'shared_roster_exceptions' };
    }
    const assigned = intervals(other?.weekly_roster);
    if (!assigned || assigned.length === 0) return { ok: false, reason: 'shared_roster_unknown' };
    for (const [start, end] of requested) {
      if (assigned.some(([otherStart, otherEnd]) => start < otherEnd && otherStart < end)) {
        return { ok: false, reason: 'roster_overlap' };
      }
    }
  }
  return { ok: true, reason: '' };
}
