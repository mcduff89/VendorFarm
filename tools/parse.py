import re, sys, pickle
TABLES = {'creature_template','creature_loot_template','reference_loot_template','item_template','creature','skinning_loot_template'}
def tuples(s):
    # s: "(...),(...);"
    i=0; n=len(s); out=[]
    while i<n:
        if s[i]=='(':
            i+=1; row=[]; cur=''; inq=False
            while True:
                c=s[i]
                if inq:
                    if c=='\\': cur+=s[i+1]; i+=2; continue
                    if c=="'": inq=False; i+=1; continue
                    cur+=c; i+=1; continue
                if c=="'": inq=True; isstr=True; i+=1; continue
                if c==',': row.append(cur); cur=''; i+=1; continue
                if c==')': row.append(cur); i+=1; break
                cur+=c; i+=1
            out.append(row)
        else: i+=1
    return out
data={t:[] for t in TABLES}
cols={}
cur=None
with open(sys.argv[1],encoding='utf-8',errors='replace') as f:
    for line in f:
        m=re.match(r'CREATE TABLE `(\w+)`',line)
        if m: cur=m.group(1); 
        if cur in TABLES and line.strip().startswith('`'):
            cols.setdefault(cur,[]).append(line.split('`')[1])
        m=re.match(r'INSERT INTO `(\w+)` VALUES ',line)
        if m and m.group(1) in TABLES:
            data[m.group(1)].extend(tuples(line[m.end():]))
for t in TABLES: print(t,len(data[t]),len(cols[t]), len(data[t][0]) if data[t] else 0)
pickle.dump((cols,data),open(sys.argv[2],'wb'))
