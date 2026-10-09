"""Prepare the versioned training content and copy selected existing original art.
No image modification; full files and source/prompt hashes are preserved.
"""
import argparse, hashlib, json, shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
P = ROOT / 'project'

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def sentence(op, amount, target='enemy', **kw):
    return dict(op=op, amount=amount, target=target, **kw)

def variant(id, name, family, cost, rows, desc, **kw):
    rows = [dict(s, id=f's{i+1}') for i, s in enumerate(rows)]
    return dict(id=id, name=name, source_family_id=family, version=1,
                capacity=3, prepared_qi_cost=cost, hp_cost=0,
                sentences=rows, description=desc, icon=kw.pop('icon', 'blade'), **kw)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', default='D:/novel/game')
    a = ap.parse_args()
    source = Path(a.source)
    V = []
    def add(*args, **kwargs):
        V.append(variant(*args, **kwargs))
    add('sword', '青锋诀', 'qingfeng', 160, [sentence('damage',320)], '单句直伤，下一自身窗口即可再用。')
    add('sword_deep', '青锋诀·凝练', 'qingfeng', 390, [sentence('damage',780)], '固定强化成品；提高效量，仍为单句。')
    add('sword_echo', '青锋诀·双斩', 'qingfeng', 320, [sentence('damage',320, repeat=2)], '两次独立出手；分别处理锋锐与护体。')
    add('ember', '藏火式·余烬', 'canghuo', 390, [sentence('damage',650), sentence('apply',{'ref':'s1','field':'actual','num':1,'den':3,'round':'floor'}, buff='侵袭')], '按前句实际气血损失施加侵袭，护体吸收部分不计。', icon='dart')
    add('ember_guard', '藏火式·归炉', 'canghuo', 470, [sentence('damage',650), sentence('apply',{'ref':'s1','field':'actual','num':1,'den':3,'round':'floor'}, buff='侵袭'), sentence('apply',{'ref':'s2','field':'actual','num':2,'den':1}, target='self', buff='护体')], '直伤 → 实际侵袭 → 实际护体，派生量不重复放大。', icon='dart')
    add('guard', '金屏诀', 'jinping', 220, [sentence('apply',350,'self',buff='护体')], '护体吸收直接伤害；不挡侵袭、蚀骨或气血支付。', icon='guard')
    add('guard_spring', '金屏诀·回春', 'jinping', 350, [sentence('apply',350,'self',buff='护体'), sentence('apply',35,'self',buff='回春')], '护体加回春；回春每公共刻生效后减一层。', icon='guard')
    add('heal', '归元诀', 'guiyuan', 340, [sentence('heal',450,'self')], '即时恢复气血，溢出不保存。', icon='herb')
    add('heal_clean', '归元诀·清浊', 'guiyuan', 400, [sentence('heal',420,'self'), sentence('remove',99999,'self',buff='debuffs')], '恢复气血并清除减益；不清增益和印记。', icon='herb')
    add('qi', '纳气诀', 'naqi', 0, [sentence('qi',400,'self')], '零费用供气，每窗一次，满灵气时会溢出。', icon='inner_e')
    add('qi_flow', '纳气诀·周天', 'naqi', 80, [sentence('qi',400,'self'), sentence('apply',18,'self',buff='鲸吞')], '供气并提高每公共刻自然回气。', icon='inner_e')
    add('seal', '无常印', 'wuchang_seal', 120, [sentence('apply',90,buff='无常印记')], '印记只保存层数；供断印式读取或消耗。', icon='fine')
    add('seal_burst', '断印式', 'duanyin', 260, [sentence('consume',90,buff='无常印记', required=True), sentence('damage',{'ref':'s1','field':'actual','num':9,'den':1})], '至少90印记才能开始；显式消耗一次，再按实际消耗出手。', requires={'buff':'无常印记','min':90})
    add('pressure', '逆流诀', 'niliu', 300, [sentence('apply',55,buff='逆气'),sentence('apply',35,buff='滞气'),sentence('apply',5,buff='蚀骨')], '提高实付费用、压回气、窗口前蚀骨；不改变回转。', icon='inner_y')
    add('edge', '养锋诀', 'yangfeng', 180, [sentence('apply',180,'self',buff='锋锐'),sentence('apply',2,'self',buff='神速')], '锋锐逐出手消耗一层；神速改战机增长，不改速度排序。')
    add('calm', '静心诀', 'jingxin', 140, [sentence('apply',90,'self',buff='凝神')], '降低主动施法费用，保留基础承载与N。', icon='inner_e')
    artifacts = []
    def artifact(id, name, F, trigger, auto, cost, rows, desc, **kw):
        artifacts.append(dict(id=id,name=name,source_family_id=id,F=F,trigger=trigger,
                              auto=auto,active=variant('artifact_'+id, name+'·催',id,cost,rows,desc),
                              description=desc, **kw))
    artifact('iron', '灵铁剑',5,'window',[sentence('damage',5)],10,[sentence('apply',5,buff='撕裂')],'原样例：每窗5点直伤；催动施加5撕裂。')
    artifact('robe', '金缕衣',5,'entry',[sentence('apply',20,'self',buff='护体')],5,[sentence('apply',5,'self',buff='护体')],'原样例：入场20护体；催动5护体。')
    artifact('jade', '镇心玉·训练',25,'entry',[sentence('apply',280,'self',buff='护体')],100,[sentence('apply',340,'self',buff='护体')],'入场一次护体；催动独立入口。')
    artifact('blade', '鸣霄剑·训练',30,'window',[sentence('damage',100)],160,[sentence('damage',290)],'每自身窗开始100直伤；催动290直伤。')
    artifact('talisman', '回澜符·训练',25,'low_health',[sentence('apply',700,'self',buff='护体')],180,[sentence('heal',400,'self')],'受伤后存活且首次低于40%气血，触发一次700护体；不救致死伤。', threshold=40)
    artifact('bell', '清声铃·训练',20,'entry',[sentence('apply',35,'self',buff='凝神')],180,[sentence('remove',99999,'self',buff='debuffs')],'入场一次35凝神；催动清除减益。')
    loadouts = {
        'balanced': {'name':'攻守兼备','slots':['sword_deep','ember','guard','qi'],'artifacts':['jade','blade']},
        'seal': {'name':'印记兑现','slots':['seal','seal_burst','guard','qi'],'artifacts':['jade','blade']},
        'pressure': {'name':'持续施压','slots':['sword_deep','pressure','heal_clean','qi_flow'],'artifacts':['talisman','bell']}
    }
    chars = []
    for id,name,label,stats,art in [
        ('C01','沈青岚','均衡',[3000,1600,70,121],'c01_qingshan'),
        ('C02','陆玄钧','储备',[3600,2000,55,100],'c04_xuantie'),
        ('C03','江听澜','周转',[2700,1400,100,121],'c05_shuiwen'),
        ('C04','叶逐风','疾行',[2700,1200,60,196],'c09_wuyi')]:
        chars.append(dict(id=id,name=name,label=label,stats=dict(zip(['Hmax','M','Q','S'],stats)),
                          mastery=dict(control=1,economy=100,potency=100,division=1),
                          sword_damage=100,art=art,loadout='balanced'))
    enemies = [
        dict(id='P01',name='赤角炎牛',type='野怪',description='专注直伤的野怪；观察护体与基础周转。',stats=dict(Hmax=2400,M=1200,Q=55,S=100),slots=['sword_deep','sword_echo_beast','edge','qi'],artifacts=[],ai='easy',art='cinder_horn_ox',sword_damage=120),
        dict(id='P02',name='守亭修士',type='NPC',description='防护恢复与余烬输出并用的固定对手。',stats=dict(Hmax=3000,M=1600,Q=70,S=121),slots=['ember','guard_spring','heal','qi'],artifacts=['jade','blade'],ai='normal',art='c03_zhuhuang',sword_damage=100),
        dict(id='P03',name='逆流客',type='NPC',description='以费用和持续状态施压；有限预演策略。',stats=dict(Hmax=3000,M=1600,Q=70,S=121),slots=['pressure','sword_deep','heal_clean','qi_flow'],artifacts=['talisman','bell'],ai='hard',art='c02_chiyi',sword_damage=100)
    ]
    # P01 has two independent mother-method families, never renamed same-source copies.
    enemies[0]['slots'][1]='ember'
    for enemy in enemies:
        enemy['mastery']=dict(control=1,economy=100,potency=100,division=1)
    difficulties = [dict(id=id,name=name,percent=pct,ai=id) for id,name,pct in [('easy','简单',80),('normal','普通',100),('hard','困难',120)]]
    save(P/'data/content.json',dict(version='training-v2.1',rules='own-window-1.0',characters=chars,
         techniques=V,artifacts=artifacts,loadouts=loadouts,enemies=enemies,difficulties=difficulties,
         limits=dict(ticks=600,windows=100),ai=dict(beam=8,nodes=256,max_ticks=64,max_windows=4,max_events=256,window_events=30000,swaps=3)))
    manifest = []
    def copy(src, dest):
        dest = P / 'assets' / dest
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(src,dest)
        manifest.append(dict(path=dest.relative_to(P).as_posix(),source=str(src),sha256=hashlib.sha256(dest.read_bytes()).hexdigest()))
    chroot=source/'素材库/01_人物动画/characters_frames_v1'
    for char in sorted({c['art'] for c in chars}|{'c03_zhuhuang','c02_chiyi'}):
        for action in ['attack','cast_1','cast_2']:
            copy(chroot/char/'exports'/f'{action}_strip.png',f'characters/{char}/{action}.png')
        for name in ['prompt.txt','meta.json']:
            copy(chroot/char/name,f'characters/{char}/{name}')
    boss=source/'素材库/02_灵兽与Boss/bosses_attack_v1'
    copy(boss/'sheets/cinder_horn_ox.png','characters/cinder_horn_ox/attack.png')
    copy(boss/'manifest.json','characters/cinder_horn_ox/source_manifest.json')
    for scene in ['battle-courtyard','battle-forest']:
        for ext in ['.png','.prompt.txt']:
            copy(source/'assets/art/combat_v2'/(scene+ext),'scenes/'+scene+ext)
    for font in ['NotoSansSC.ttf','OFL.txt','SOURCE.md']:
        copy(source/'assets/fonts'/font,'fonts/'+font)
    for icon in ['blade','guard','herb','dart','inner_e','inner_y','fine']:
        copy(source/'assets/icons'/(icon+'.svg'),'icons/'+icon+'.svg')
    for lic in (source/'assets/licenses').glob('*.txt'):
        copy(lic,'licenses/'+lic.name)
    for sound in ['hit','select','complete']:
        if (source/'assets/sfx'/(sound+'.wav')).exists():
            copy(source/'assets/sfx'/(sound+'.wav'),'sfx/'+sound+'.wav')
    copy(source/'assets/icon.svg','icon.svg')
    save(P/'assets/SOURCES.json',manifest)
    print(f'Prepared {len(V)} techniques, {len(artifacts)} artifacts; copied {len(manifest)} source files.')

if __name__=='__main__':
    main()
