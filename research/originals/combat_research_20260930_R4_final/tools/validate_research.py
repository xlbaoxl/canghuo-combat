# -*- coding: utf-8 -*-
"""Validate only this research package. No games, network or external tools used."""
from pathlib import Path
from urllib.parse import unquote
import csv,json,re,hashlib,sys
ROOT=Path(__file__).resolve().parents[1]
GAMES=['觅长生','圣兽之王','弈仙牌','太吾绘卷']
REF=r'(?<![A-Z0-9-])(?:(?:R2-(?:AR|ES|BG|IF)-)?(?:MCS|UO|YXP|TW)-(?:E|P)\d+|R3-(?:MCS|UO|YXP|TW)-[A-Z]+\d+)'
def read(name):return json.loads((ROOT/name).read_text(encoding='utf-8-sig'))
def rows(name):
 with (ROOT/name).open(encoding='utf-8-sig',newline='') as f:return list(csv.DictReader(f))
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
 e=rows('evidence.csv');c=rows('coverage.csv');disc=rows('discoveries.csv')
 case=read('data/final_cases.json');p=read('data/design_synthesis.json')['principles']
 exp=read('data/experience_matrix_R3.json');boundary=read('data/claim_boundaries.json')
 eid={r['evidence_id'] for r in e};sid={s['source_id'] for s in exp['sources']};cid={s['claim_id'] for s in exp['claims']}
 assert len(eid)==len(e)==211
 assert len(sid)==len(exp['sources'])==37 and sid<=eid
 assert len(cid)==len(exp['claims'])==41 and len(exp['answers'])==24
 assert len(c)==len(case['records'])==64 and len({r['record_id'] for r in c})==64
 assert len(disc)==len({d['discovery_id'] for d in disc})==32
 assert len(rows('variables.csv'))==74 and len(rows('relations.csv'))==46
 assert len(boundary['disputes'])==12 and len(boundary['scope_notes'])==4
 assert len(boundary['closed_questions'])==6 and all(len(q['per_game'])==4 for q in boundary['closed_questions'])
 assert len(p)==8 and {x['id'] for x in p}=={f'R4-P{i:02}' for i in range(1,9)}
 known=eid|cid
 for g in GAMES:
  rs=[x for x in c if x['game']==g]
  assert {x['question_id'] for x in rs}=={f'D{i:02}' for i in range(1,17)}
  body=(ROOT/'cases'/f'{g}.md').read_text(encoding='utf-8-sig')
  assert all(f'id="d{i:02}"' in body for i in range(1,17))
  assert body.count('**研究状态：**')==16
  assert '阶段与压力（Q3）' in body and '原作战斗实测' in body
  for r in rs:
   j=next(x for x in case['records'] if x['record_id']==r['record_id'])
   for key in ['progress','presence_judgment','evidence_status','summary','decision_and_cost','limitations','game_scope']:
    assert r[key] and r[key]==j[key],(g,r['question_id'],key)
   assert j['summary'].replace('準备','准备') in body
   assert set(j['evidence_ids'])<=eid and set(j['experience_ids'])<=sid
   assert set(j['stage_source_ids'])<=sid
   assert all(next(z['game'] for z in e if z['evidence_id']==i)==g for i in j['evidence_ids'])
 for pp in p:
  assert set(pp['per_game'])==set(GAMES)
  for k in ['common_problem','conclusion','benefits','applies_when','costs','breaks_when','conflicting_combinations','do_not_infer','design_review_question','review_check']:assert pp[k],(pp['id'],k)
  for g,v in pp['per_game'].items():
   assert v['native_relation'] and v['boundary'] and set(v['evidence_ids'])<=eid
   assert all(next(z['game'] for z in e if z['evidence_id']==i)==g for i in v['evidence_ids'])
  assert pp['conclusion'] in (ROOT/'design_principles.md').read_text(encoding='utf-8')
 for a in exp['answers']:
  assert a['finding'] and a['limits'] and set(a['source_ids'])<=sid and set(a['claim_ids'])<=cid and set(a['mechanism_evidence_ids'])<=eid
 for a in exp['claims']:assert a['claim'] and a['limits'] and set(a['source_ids'])<=sid and set(a['mechanism_evidence_ids'])<=eid
 for a in exp['sources']:
  assert a['full_text_read'] is True and a['url'].startswith('https://')
  assert a['published_at'] and a['version'] and a['limits']
  assert re.fullmatch('[0-9a-f]{64}',a['sha256']) and len(a['quote'])<=300
 for d in disc:
  assert d['final_disposition'] and d['current_boundary'] and d['confirmed_correspondences']
  assert set(d['conditional_principles'].split('；'))<={x['id'] for x in p}
 doc_ids={x['id'] for x in boundary['document_evidence']}
 for d in boundary['disputes']:assert set(d['evidence_ids'])<=known|doc_ids,d['id']
 refs=links=anchors=0
 for f in ROOT.rglob('*.md'):
  body=f.read_text(encoding='utf-8-sig');assert '\ufffd' not in body,f
  for ref in re.findall(REF,body):assert ref in known,(f.name,ref);refs+=1
  for target in re.findall(r'\]\(([^)]+)\)',body):
   target=unquote(target.strip('<>'))
   if '://' in target or re.match(r'^[A-Za-z]:',target):continue
   loc,_,anc=target.partition('#');dest=(f.parent/loc).resolve() if loc else f
   assert dest.is_relative_to(ROOT),('Nonportable link',f.name,target)
   assert dest.exists(),('Missing link',f.name,target);links+=1
   if anc:assert f'id="{anc}"' in dest.read_text(encoding='utf-8-sig'),('Missing anchor',f.name,target);anchors+=1
 for f in ROOT.glob('*.csv'):
  for row in rows(f.name):
   for ref in re.findall(REF,' '.join(row.values())):assert ref in known,(f.name,ref);refs+=1
 # Validate current JSON editorial files, excluding exact historical copies with
 # their own historical source identifiers and locators.
 for name in ['final_cases.json','design_synthesis.json','mechanism_audit.json','claim_boundaries.json']:
  for ref in re.findall(REF,(ROOT/'data'/name).read_text(encoding='utf-8')):
   assert ref in known,(name,ref);refs+=1
 body=(ROOT/'comparison.md').read_text(encoding='utf-8')
 assert all(f'id="d{i:02}"' in body for i in range(1,17))
 assert len(re.findall(r'^\| \[D\d{2}',body,re.M))==16
 assert body.count('**四作定位：**')==16
 forbidden=[str(f.relative_to(ROOT)) for f in ROOT.rglob('*') if f.is_file() and f.suffix.lower() not in {'.md','.csv','.json','.py'}]
 assert not forbidden,forbidden
 result=dict(status='PASS',round='R4-final',games=4,dimension_cells=64,case_chapters=64,comparison_questions=16,conditional_principles=8,principle_game_cells=32,final_disputes=12,discoveries_closed=32,variables=74,relations=46,cumulative_evidence=211,public_sources=37,interpretive_claims=41,experience_cells=24,evidence_and_claim_references_checked=refs,relative_links_checked=links,anchor_links_checked=anchors,original_combat_tests=0,new_public_sources=0,scope='Research structure, attribution, current prose/data consistency and portable references only. Historical source checks and archive lineage are separately reported in provenance_R4.json. No commercial game test or full engine reconstruction.')
 result_text=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
 if '--build' not in sys.argv:
  mf=read('data/file_manifest.json')['files'];assert mf
  paths={f.relative_to(ROOT).as_posix() for f in ROOT.rglob('*') if f.is_file() and f.relative_to(ROOT).as_posix()!='data/file_manifest.json'}
  assert paths=={x['path'] for x in mf},'Manifest inventory mismatch'
  for x in mf:
   f=ROOT/x['path'];assert f.stat().st_size==x['bytes'] and digest(f)==x['sha256'],('Manifest mismatch',x['path'])
  assert (ROOT/'data/package_validation.json').read_text(encoding='utf-8')==result_text,'Validation result changed since manifest build'
 (ROOT/'data/package_validation.json').write_text(result_text,encoding='utf-8')
 print(result_text)
 if '--build' not in sys.argv:print('File manifest verified.')
if __name__=='__main__':main()
