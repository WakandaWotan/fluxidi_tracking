import {assertFinancialAcceptanceFenceV1} from './financial_acceptance_fence_v1.mjs';
// Explicit local migration required. Adapter is imported; no production binding or migration is activated.
export const FINANCIAL_ROUTE_EVIDENCE_SCHEMA = `CREATE TABLE IF NOT EXISTS financial_route_evidence_v1 (
  evidence_key TEXT PRIMARY KEY NOT NULL,
  payload_json TEXT NOT NULL
)`;
export class D1FinancialRouteEvidenceStorage {
  constructor(db) {
    if (typeof db?.prepare !== 'function') throw new Error('financial_evidence_database_required');
    // Recovery must not infer absence from a stale read replica.
    this.db=typeof db.withSession==='function' ? db.withSession('first-primary') : db;
  }
  async get(key) {
    const row=await this.db.prepare('SELECT payload_json FROM financial_route_evidence_v1 WHERE evidence_key = ?').bind(key).first();
    return row ? JSON.parse(row.payload_json) : undefined;
  }
  async insertIfAbsent(key,value) {
    const result=await this.db.prepare('INSERT OR IGNORE INTO financial_route_evidence_v1 (evidence_key, payload_json) VALUES (?, ?)')
      .bind(key,JSON.stringify(value)).run();
    if (result.success !== true) throw new Error('financial_evidence_write_failed');
    return result.meta?.changes === 1;
  }
  async compareAndSet(key, expected, value) {
    const result=await this.db.prepare('UPDATE financial_route_evidence_v1 SET payload_json = ? WHERE evidence_key = ? AND payload_json = ?')
      .bind(JSON.stringify(value),key,JSON.stringify(expected)).run();
    if(result.success!==true)throw new Error('financial_evidence_write_failed');
    return result.meta?.changes===1;
  }
  async assertCloseFence(){await assertFinancialAcceptanceFenceV1(this.db);}
  async hasCloseFence(){try{await this.assertCloseFence();return true;}catch{return false;}}
}
