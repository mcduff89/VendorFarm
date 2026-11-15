import pickle, sys, collections, math
cols,data=pickle.load(open(sys.argv[1],'rb'))
def rows(t):
    c=cols[t]
    for r in data[t]: yield dict(zip(c,r))
items={}
for r in rows('item_template'):
    items[int(r['entry'])]=(r['name'],int(r['Quality']),int(r['SellPrice']),int(r['class']))
def loadloot(t):
    d=collections.defaultdict(list)
    for r in rows(t):
        d[int(r['entry'])].append((int(r['item']),float(r['ChanceOrQuestChance']),int(r['groupid']),int(r['mincountOrRef']),int(r['maxcount']),int(r['condition_id'])))
    return d
cl=loadloot('creature_loot_template'); rl=loadloot('reference_loot_template'); sl=loadloot('skinning_loot_template')
memo={}
def expect(tbl,entry,depth=0):
    """returns dict itemID->expected count per roll of this loot table"""
    key=(id(tbl),entry)
    if key in memo: return memo[key]
    out=collections.defaultdict(float)
    if depth>6: return out
    groups=collections.defaultdict(list)
    for it,ch,g,mc,mx,cond in tbl.get(entry,[]):
        if ch<0: continue   # quest-only
        if cond: pass       # conditions: keep (usually quest/faction); rare
        groups[g].append((it,ch,mc,mx))
    def add(it,p,mc,mx):
        if mc<0:
            sub=expect(rl,-mc,depth+1)
            times=max(mx,1)
            for k,v in sub.items(): out[k]+=p*times*v
        else:
            avg=(max(mc,1)+max(mx,mc,1))/2.0
            out[it]+=p*avg
    for g,lst in groups.items():
        if g==0:
            for it,ch,mc,mx in lst: add(it,ch/100.0,mc,mx)
        else:
            expl=[x for x in lst if x[1]>0]; eq=[x for x in lst if x[1]==0]
            s=sum(x[1] for x in expl)
            scale=1.0 if s<=100 else 100.0/s
            for it,ch,mc,mx in expl: add(it,ch/100.0*scale,mc,mx)
            rem=max(0.0,100.0-s)/100.0
            if eq:
                for it,ch,mc,mx in eq: add(it,rem/len(eq),mc,mx)
    memo[key]=out
    return out
spawns=collections.Counter(); maps=collections.defaultdict(collections.Counter); resp=collections.defaultdict(list)
for r in rows('creature'):
    i=int(r['id']); spawns[i]+=1; maps[i][int(r['map'])]+=1; resp[i].append((int(r['spawntimesecsmin'])+int(r['spawntimesecsmax']))/2)
out=[]; used=set()
stats=collections.Counter()
for r in rows('creature_template'):
    e=int(r['Entry']); 
    if spawns[e]==0: stats['nospawn']+=1; continue
    mn,mx=int(r['MinLevel']),int(r['MaxLevel'])
    if mx>63 or mx<1: stats['lvl']+=1; continue
    rank=int(r['Rank'])
    DUNGEONS={33,34,36,43,47,48,70,90,109,129,189,209,229,230,289,329,349,389,429}
    if rank==3 and maps[e].most_common(1)[0][0] not in DUNGEONS: stats['boss']+=1; continue
    ctype=int(r['CreatureType'])
    if ctype==8: stats['critter']+=1; continue   # critter
    if int(r['NpcFlags'])!=0: stats['npcflags']+=1; continue  # vendors/questgivers etc
    uf=int(r['UnitFlags'])
    if uf & (0x2|0x100|0x200|0x2000000): stats['unattackable']+=1; continue  # NON_ATTACKABLE, IMMUNE_TO_PLAYER, IMMUNE_TO_NPC, NOT_SELECTABLE
    gmin,gmax=int(r['MinLootGold']),int(r['MaxLootGold'])
    lid=int(r['LootId']); sid=int(r['SkinningLootId'])
    ex=expect(cl,lid) if lid else {}
    loot=[]
    for it,ec in ex.items():
        if it not in items: continue
        nm,q,sp,cls=items[it]
        if cls==12: continue # quest items
        loot.append((it,ec,sp))
    skin=[]
    if sid and (int(r['CreatureTypeFlags'])&1):
        for it,ec in expect(sl,sid).items():
            if it in items: skin.append((it,ec,items[it][2]))
    coin=(gmin+gmax)/2.0
    ev=sum(ec*sp for it,ec,sp in loot)
    if ev+coin<=0 and not skin: stats['noloot']+=1; continue
    # keep items: top 14 by vendor value plus anything >=1% count for AH mode, cap 18
    loot.sort(key=lambda x:-(x[1]*x[2]))
    keep=[x for x in loot if x[1]*x[2]>0][:14]
    ks={x[0] for x in keep}
    extra=sorted([x for x in loot if x[0] not in ks and x[1]>=0.01], key=lambda x:-x[1])[:4]
    keep+=extra; ks|={x[0] for x in extra}
    rest=sum(ec*sp for it,ec,sp in loot if it not in ks)
    skin.sort(key=lambda x:-x[1]); skin=skin[:4]
    mp=maps[e].most_common(1)[0][0]
    for x in keep+skin: used.add(x[0])
    rs=sorted(resp[e]); rsp=round(rs[len(rs)//2])
    out.append((e,r['Name'],mn,mx,rank,round(coin),maps[e][mp],mp,keep,round(rest),skin,rsp))
    stats['kept']+=1
print(stats, file=sys.stderr)
def lstr(s): return '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'
def fmt(lst): return ';'.join(f"{it}:{round(ec*10000)}" for it,ec,sp in lst if round(ec*10000)>0)
with open(sys.argv[2],'w') as f:
    f.write("-- VendorFarm data. Generated from CMaNGOS Classic-DB (GPL-3.0, github.com/cmangos/classic-db, z2815).\n")
    f.write("-- Drop chances are the emulator database's vanilla 1.12 values, not measured on WoW Forever.\n")
    f.write("-- Mob: \"name|minLvl|maxLvl|rank|avgCoinCopper|spawnCount|mapID|items|restCopper|skin|respawnSec\"\n")
    f.write("-- items/skin: itemID:expectedCountPerKill*10000 separated by ';'\n")
    f.write("local _, ns = ...\nns.MOBS = {\n")
    for e,nm,mn,mx,rank,coin,sp,mp,keep,rest,skin,rsp in out:
        f.write(f"[{e}]={lstr(f'{nm}|{mn}|{mx}|{rank}|{coin}|{sp}|{mp}|{fmt(keep)}|{rest}|{fmt(skin)}|{rsp}')},\n")
    f.write("}\n")
with open(sys.argv[3],'w') as f:
    f.write("-- VendorFarm item fallback data (CMaNGOS Classic-DB). Live GetItemInfo sell prices override these.\n")
    f.write("-- \"name|quality|sellPriceCopper\"\nlocal _, ns = ...\nns.ITEMS = {\n")
    for it in sorted(used):
        nm,q,sp,cls=items[it]
        f.write(f"[{it}]={lstr(f'{nm}|{q}|{sp}')},\n")
    f.write("}\n")
print(len(out),len(used))
