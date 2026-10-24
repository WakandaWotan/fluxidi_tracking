// One immutable advisory dispatch snapshot owns this cache. Key includes the
// exact timestamp and all schedule inputs. Account, pause, manual override,
// presence, lease and reservation state are deliberately evaluated every time.
export function createRosterSnapshotCache({maxEntries=2048}={}) {
 if(!Number.isInteger(maxEntries)||maxEntries<1||maxEntries>4096)throw Error('roster_cache_limit_invalid');
 const entries=new Map();return{get size(){return entries.size;},resolve(roster,atMs,exceptions,run){
  const key=JSON.stringify([roster,atMs,exceptions]);if(entries.has(key))return structuredClone(entries.get(key));
  const value=run();if(entries.size<maxEntries)entries.set(key,structuredClone(value));return value;
 }};
}
