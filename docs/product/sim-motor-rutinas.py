# Simulación en Python de la selección de ejercicios de BlockPlanner/ExerciseAssigner (auditoría 2026-10-24).
# Lee exercises.json y exercise-staples.json reales. Evidencia de la auditoría; se vuelve obsoleto con PR-B001.
# Uso: python3 docs/product/sim-motor-rutinas.py
import json, itertools, collections
import os
base=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Packages", "PRCore", "Sources", "PRCore", "Resources")
ex={e["id"]:e for e in json.load(open(f"{base}/exercises.json"))}
staples=json.load(open(f"{base}/exercise-staples.json"))
names=json.load(open(f"{base}/exercise-names-es.json"))
eqmap={"barbell":"barbell","dumbbell":"dumbbell","cable":"cable","machine":"machine","body only":"bodyweight","bands":"bands","kettlebells":"kettlebell","e-z curl bar":"barbell","other":"other","medicine ball":"other","exercise ball":"other"}
AVAIL={"barbell","dumbbell","machine","cable","bodyweight"}
ROT={"stable":1,"balanced":2,"varied":3}
VOL=8  # normal tier lower bound
PRIOR=["chest","back","shoulders","biceps","triceps","quadriceps","hamstrings","glutes"]
SPLITS={"fullBody":[PRIOR],"upperLower":[["chest","back","shoulders","biceps","triceps"],["quadriceps","hamstrings","glutes","calves"]],"pushPullLegs":[["chest","shoulders","triceps"],["back","biceps","forearms"],["quadriceps","hamstrings","glutes","calves"]]}
def split(days,exp,goal,phase):
    if days==2: return "fullBody"
    if days==3: return "pushPullLegs" if (exp in("advanced","competitive") or goal=="bodybuilding") else "fullBody"
    if days==4: return "pushPullLegs" if (goal=="bodybuilding" and exp=="advanced" and phase=="surplus") else "upperLower"
    return "pushPullLegs"
def assign(m,variety):
    ok=[i for i in staples[m] if i in ex and eqmap.get(ex[i]["equipment"] or "","other") in AVAIL]
    return ok[0], ok[1:1+ROT[variety]]
def distribute(sets,anchor,rot,occ):
    n=1+len(rot); count=min(n,max(1,(sets+2)//3))
    if count==1 and occ>0 and rot: picked=[rot[(occ-1)%len(rot)]]
    else:
        picked=[anchor]
        if count>1 and rot:
            for step in range(count-1): picked.append(rot[(occ*(count-1)+step)%len(rot)])
    u=[]; [u.append(p) for p in picked if p not in u]
    b,r=divmod(sets,len(u)); return [(p,b+(1 if i<r else 0)) for i,p in enumerate(u)]
REST={"strength":150,"powerbuilding":120}
def dur(items,goal):
    rest=REST.get(goal,60); n=sum(s for _,s in items)
    return n*(60+rest)+(n-1)*30
def plan(days,variety,goal="hypertrophy",exp="intermediate",phase="maintenance",minutes=60):
    sp=split(days,exp,goal,phase); classes=SPLITS[sp]
    daysplans=[classes[i%len(classes)] for i in range(days)]
    dbm=collections.defaultdict(list)
    for i,d in enumerate(daysplans):
        for m in d: dbm[m].append(i)
    out=[]
    for i,d in enumerate(daysplans):
        chosen=collections.OrderedDict()
        for m in d:
            if m not in PRIOR: continue
            a,r=assign(m,variety); md=dbm[m]; pos=md.index(i)
            st=VOL//len(md)+(1 if pos< VOL%len(md) else 0)
            for e,s in distribute(st,a,r,pos): chosen[e]=chosen.get(e,0)+s
        items=list(chosen.items())
        if minutes:
            while dur(items,goal)>minutes*60:
                idx=[k for k,(e,s) in enumerate(items) if s>1]
                if not idx: break
                e,s=items[idx[-1]]; items[idx[-1]]=(e,s-1)
        out.append((sp,items))
    return out
def show(days,variety,goal="hypertrophy",exp="intermediate",phase="maintenance",minutes=60):
    print(f"\n### {days} días · {variety} · {goal} · {exp} · {minutes} min")
    for i,(sp,items) in enumerate(plan(days,variety,goal,exp,phase,minutes)):
        tot=sum(s for _,s in items)
        print(f"  Día {i+1} [{sp}] {len(items)} ej / {tot} series / ~{dur(items,goal)//60} min: "+", ".join(f"{names.get(e,e)} x{s}" for e,s in items))
for v in ["stable","balanced","varied"]:
    show(3,v)
show(3,"balanced",minutes=90); show(3,"balanced",minutes=30); show(3,"balanced",goal="strength"); show(3,"balanced",exp="advanced"); show(3,"balanced",exp="novice",goal="generalHealth")
show(4,"balanced"); show(4,"stable"); show(5,"balanced"); show(6,"balanced"); show(6,"stable"); show(2,"balanced")
# Matrix of unique exercise sets
print("\n=== Matriz: ¿cuántas rutinas DISTINTAS (conjunto de ejercicios) salen de todas las combinaciones?")
combos=set(); allc=0
for days in range(2,8):
  for v in ROT:
    for goal in ["strength","powerbuilding","hypertrophy","bodybuilding","recomposition","generalHealth"]:
      for exp in ["novice","beginner","intermediate","advanced","competitive"]:
        for phase in ["surplus","maintenance","deficit"]:
          for minutes in [30,45,60,90,120]:
            allc+=1
            sig=tuple(tuple(sorted(e for e,_ in items)) for _,items in plan(days,v,goal,exp,phase,minutes))
            combos.add((days,sig))
print("combinaciones de perfil evaluadas:",allc)
print("rutinas distintas por conjunto de ejercicios:",len(combos))
by=collections.Counter(d for d,_ in combos); print("distintas por nº de días:",dict(by))
