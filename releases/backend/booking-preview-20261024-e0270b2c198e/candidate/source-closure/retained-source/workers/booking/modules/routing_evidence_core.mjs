// Exact directed, edge-expanded graph. Incoming-edge states preserve turn rules.
// Certificates apply only to this graph's explicit oracle contract, never to an
// unrelated OSM/Mapbox graph. Snapping must already resolve to these node IDs.
export const EvidenceClass = Object.freeze({
  LOWER: 'CERTIFIED_LOWER_BOUND', UPPER: 'CERTIFIED_UPPER_BOUND',
  STATIC: 'EXACT_STATIC_ROUTE', TRAFFIC: 'TRAFFIC_ESTIMATE', ADVISORY: 'ADVISORY_ONLY',
});
class Heap {
  constructor() { this.values = []; }
  push(pair) {
    const a = this.values; let i = a.length; a.push(pair);
    while (i) { const p = (i - 1) >> 1; if (a[p][0] <= pair[0]) break; a[i] = a[p]; i = p; }
    a[i] = pair;
  }
  pop() {
    const a = this.values; if (!a.length) return null;
    const first = a[0], last = a.pop();
    if (a.length) {
      let i = 0;
      while (2 * i + 1 < a.length) {
        let c = 2 * i + 1; if (c + 1 < a.length && a[c + 1][0] < a[c][0]) c++;
        if (a[c][0] >= last[0]) break; a[i] = a[c]; i = c;
      }
      a[i] = last;
    }
    return first;
  }
}
export class DirectedRoadGraph {
  constructor({ nodes, edges, turns = [], version, profile = 'car' }) {
    if (!Number.isSafeInteger(nodes) || nodes < 1 || nodes > 100000 ||
        !Array.isArray(edges) || edges.length > 500000 || !version) throw Error('graph_invalid');
    this.nodes = nodes; this.version = String(version); this.profile = profile;
    this.edges = edges.map((e, id) => {
      if (!Number.isInteger(e.from) || !Number.isInteger(e.to) || e.from < 0 ||
          e.to < 0 || e.from >= nodes || e.to >= nodes ||
          !Number.isFinite(e.minimum) || e.minimum < 0) throw Error('graph_edge_invalid');
      return Object.freeze({ ...e, id });
    });
    const restrictions = new Map();
    for (const t of turns) {
      if (!this.edges[t.fromEdge] || !this.edges[t.toEdge] ||
          this.edges[t.fromEdge].to !== this.edges[t.toEdge].from ||
          !Number.isFinite(t.minimum ?? 0) || (t.minimum ?? 0) < 0) throw Error('graph_turn_invalid');
      restrictions.set(t.fromEdge + ':' + t.toEdge, Object.freeze({ ...t }));
    }
    const outgoing = Array.from({ length: nodes }, () => []);
    const incoming = Array.from({ length: nodes }, () => []);
    for (const e of this.edges) { outgoing[e.from].push(e); incoming[e.to].push(e); }
    this.reverse = Array.from({ length: nodes + edges.length }, () => []);
    this.targetStates = Array.from({ length: nodes }, (_, id) => [id]);
    this.transitions = 0;
    for (const e of this.edges) this.targetStates[e.to].push(nodes + e.id);
    for (let node = 0; node < nodes; node++) {
      for (const previous of [null, ...incoming[node]]) for (const next of outgoing[node]) {
        const turn = previous && restrictions.get(previous.id + ':' + next.id);
        if (turn?.disabled) continue;
        this.reverse[nodes + next.id].push({
          from: previous ? nodes + previous.id : node, edge: next.id,
          minimumTurn: turn?.minimum ?? 0,
        });
        if (++this.transitions > 2000000) throw Error('graph_transition_limit');
      }
    }
    // Float addition is not associative. Reverse and forward fractional paths
    // can differ at equal-ETA ties, so only exact safe-integer envelopes can
    // certify exclusion. Other graphs remain usable as advisory estimates.
    let integral = true, maxEdge = 0n, maxTurn = 0n;
    for (const edge of this.edges) {
      if (!Number.isSafeInteger(edge.minimum)) integral = false;
      else if (BigInt(edge.minimum) > maxEdge) maxEdge = BigInt(edge.minimum);
    }
    for (const turn of restrictions.values()) {
      const minimum = turn.minimum ?? 0;
      if (!Number.isSafeInteger(minimum)) integral = false;
      else if (BigInt(minimum) > maxTurn) maxTurn = BigInt(minimum);
    }
    this.certifiedIntegerEnvelope = integral &&
      BigInt(this.reverse.length) * (maxEdge + maxTurn) <= BigInt(Number.MAX_SAFE_INTEGER);
    Object.freeze(this.edges);
    for (const row of this.reverse) { for (const t of row) Object.freeze(t); Object.freeze(row); }
    for (const row of this.targetStates) Object.freeze(row);
    Object.freeze(this.reverse); Object.freeze(this.targetStates); Object.freeze(this);
  }
  manyToOne(target, { costs, closed = new Set() } = {}) {
    if (!Number.isInteger(target) || target < 0 || target >= this.nodes) throw Error('graph_target_invalid');
    if (costs && (costs.length !== this.edges.length || costs.some((v, i) =>
        !Number.isFinite(v) || v < this.edges[i].minimum))) throw Error('oracle_violates_lower_envelope');
    const dist = new Float64Array(this.reverse.length); dist.fill(Infinity);
    const heap = new Heap(); let settled = 0, relaxed = 0;
    for (const state of this.targetStates[target]) { dist[state] = 0; heap.push([0, state]); }
    while (heap.values.length) {
      const [cost, state] = heap.pop(); if (cost !== dist[state]) continue; settled++;
      for (const transition of this.reverse[state]) {
        if (costs && (closed.has(transition.edge) || this.edges[transition.edge].disabled)) continue;
        const weight = (costs ? costs[transition.edge] : this.edges[transition.edge].minimum) +
          transition.minimumTurn;
        const next = cost + weight; relaxed++;
        if (next < dist[transition.from]) { dist[transition.from] = next; heap.push([next, transition.from]); }
      }
    }
    return { seconds: dist.slice(0, this.nodes), settled, relaxed,
      stateBytes: dist.byteLength, graphVersion: this.version };
  }
  // Independent forward Dijkstra is retained as an exactness reference.
  oneToOne(origin, target, { costs, closed = new Set() } = {}) {
    if (!Number.isInteger(origin) || origin < 0 || origin >= this.nodes) throw Error('graph_origin_invalid');
    const forward = Array.from({ length: this.reverse.length }, () => []);
    this.reverse.forEach((rows, to) => rows.forEach(row => forward[row.from].push({ ...row, to })));
    const distances = new Float64Array(forward.length); distances.fill(Infinity);
    const heap = new Heap(); heap.push([0, origin]); distances[origin] = 0;
    const targets = new Set(this.targetStates[target]);
    while (heap.values.length) {
      const [cost, state] = heap.pop(); if (cost !== distances[state]) continue;
      if (targets.has(state)) return cost;
      for (const t of forward[state]) {
        if (costs && (closed.has(t.edge) || this.edges[t.edge].disabled)) continue;
        const next = cost + (costs ? costs[t.edge] : this.edges[t.edge].minimum) + t.minimumTurn;
        if (next < distances[t.to]) { distances[t.to] = next; heap.push([next, t.to]); }
      }
    }
    return Infinity;
  }
}
const issued = new WeakMap();
const contextKey = c => JSON.stringify([c.tenant_id, c.company_id, c.booking_id,
  c.leg, c.targetNode, c.profile, c.options, c.graphVersion, c.oracleContract]);
export class RoutingEvidenceProvider {
  #cache = new Map();
  constructor({ graph, maxEntries = 32, ttlMs = 60000, clock = Date.now, premium }) {
    if (!Number.isInteger(maxEntries) || maxEntries < 1 || maxEntries > 128 ||
        !Number.isFinite(ttlMs) || ttlMs <= 0 || ttlMs > 3600000) throw Error('routing_cache_limit_invalid');
    this.graph = graph; this.maxEntries = maxEntries; this.ttlMs = ttlMs;
    this.clock = clock; this.premium = premium;
    Object.defineProperty(this, "graph", { value: graph, writable: false });
    this.metrics = { queries: 0, hits: 0, misses: 0, providerCalls: 0 };
  }
  get cacheSize() { return this.#cache.size; }
  source() { return 'owned-directed-graph:' + this.graph.version; }
  compatible(c) {
    return Boolean(this.graph.certifiedIntegerEnvelope && c?.tenant_id && c.company_id && c.booking_id && c.leg &&
      c.graphVersion === this.graph.version && c.profile === this.graph.profile &&
      c.oracleContract === 'same-graph-nonnegative-edge-envelope-v1');
  }
  #roadQuery(context) {
    const key = contextKey(context), now = this.clock(); this.metrics.queries++;
    for (const [k, v] of this.#cache) if (now < v.at || now >= v.until) this.#cache.delete(k);
    const cached = this.#cache.get(key);
    if (cached) { this.metrics.hits++; return cached.value; }
    this.metrics.misses++;
    const value = this.graph.manyToOne(context.targetNode);
    if (this.#cache.size >= this.maxEntries) this.#cache.delete(this.#cache.keys().next().value);
    this.#cache.set(key, { value, at: now, until: now + this.ttlMs }); return value;
  }
  roadEstimate(context) { return structuredClone(this.#roadQuery(context)); }
  roadLowerBound(context, originNode) {
    if (!this.compatible(context)) return Object.freeze({ evidenceClass: EvidenceClass.ADVISORY, seconds: 0 });
    const seconds = this.#roadQuery(context).seconds[originNode];
    // Unreachable or missing snap is not certified exclusion evidence.
    if (!Number.isFinite(seconds) || seconds < 0) return Object.freeze({ evidenceClass: EvidenceClass.ADVISORY, seconds: 0 });
    const evidence = Object.freeze({ seconds, evidenceClass: EvidenceClass.LOWER,
      source: this.source(), graphVersion: this.graph.version });
    issued.set(evidence, { provider: this, context: contextKey(context),
      graph: this.graph, at: this.clock(), until: this.clock() + this.ttlMs });
    return evidence;
  }
  freshness(evidence, context) {
    const certificate = issued.get(evidence), now = this.clock();
    return Boolean(this.compatible(context) && certificate?.provider === this && certificate.graph === this.graph &&
      certificate.context === contextKey(context) && now >= certificate.at && now < certificate.until);
  }
  certifiedSeconds(evidence, context) {
    return this.freshness(evidence, context) ? evidence.seconds : 0;
  }
  exactRoute(originNode, context) {
    return { seconds: this.graph.oneToOne(originNode, context.targetNode,
      { costs: this.graph.edges.map(e => e.minimum) }), evidenceClass: EvidenceClass.STATIC,
      graphVersion: this.graph.version };
  }
  matrix(origins, targets) {
    const costs = this.graph.edges.map(edge => edge.minimum);
    return targets.map(target => { const row = this.graph.manyToOne(target, { costs });
      return origins.map(origin => row.seconds[origin]); });
  }
  async trafficRoute(candidate, context) {
    if (!this.premium) throw Error('traffic_provider_unavailable');
    this.metrics.providerCalls++; return this.premium(candidate, context);
  }
  geometry() { return { evidenceClass: EvidenceClass.ADVISORY, geometry: null }; }
}
export async function certifiedRoadSearch(candidates, { provider, context, evaluate }) {
  // Unknown graph/contract still evaluates all candidates. No candidate cap.
  let fallbackReason = null, rows;
  try {
    rows = candidates.map(c => ({ ...c, roadBound: provider.roadLowerBound(context, c.originNode) }));
  } catch (_) {
    // Failure of optional graph preparation cannot omit a candidate. The
    // authoritative evaluator's errors are deliberately NOT caught here.
    fallbackReason = 'road_evidence_unavailable';
    rows = candidates.map(c => ({ ...c, roadBound: null }));
  }
  const seconds = c => fallbackReason ? 0 : provider.certifiedSeconds(c.roadBound, context);
  rows.sort((a, b) => seconds(a) - seconds(b) || a.order - b.order);
  let best = null, pruned = 0, evaluated = 0; const decisions = [];
  for (const c of rows) {
    const bound = (c.readySeconds ?? 0) + seconds(c);
    // Strict inequality preserves every equal-ETA business tie.
    if (best && bound > best.pickupSeconds) { pruned++; decisions.push({ order: c.order, bound, upper: best.pickupSeconds }); continue; }
    const value = await evaluate(c); evaluated++;
    if (value?.allowed && Number.isFinite(value.pickupSeconds) && value.pickupSeconds < bound)
      throw Error('routing_oracle_contract_violated');
    if (value?.allowed && Number.isFinite(value.pickupSeconds) &&
        (!best || value.pickupSeconds < best.pickupSeconds ||
          value.pickupSeconds === best.pickupSeconds && c.order < best.order))
      best = { ...value, order: c.order };
  }
  return { best, pruned, evaluated, decisions, fallbackReason };
}
