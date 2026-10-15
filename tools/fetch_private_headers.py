import subprocess,os,re,sys,shutil
home=os.path.expanduser('~/xef-remote/src')
oss=home+'/apple-oss'
priv=home+'/privinc'
os.makedirs(priv,exist_ok=True)
objc=home+'/darling/objc4-apple/runtime'
src=sys.argv[1:] or ['objc-runtime-new.mm']
# header search roots in order
roots=[oss+'/xnu/bsd',oss+'/xnu/libsyscall',oss+'/xnu/libkern',oss+'/xnu/osfmk',oss+'/xnu/EXTERNAL_HEADERS',oss+'/xnu/bsd/sys',oss+'/xnu/bsd/machine',oss+'/Libc/include',oss+'/Libc',oss+'/libplatform/include',oss+'/libplatform/private',oss+'/libpthread',oss+'/libpthread/private',oss+'/dyld/include',oss+'/dyld/common',oss+'/dyld',oss+'/libmalloc/private',oss+'/libmalloc/include',oss+'/libdispatch',oss+'/libclosure',oss+'/Libsystem']
def find(h):
    out=[]
    for r in roots:
        for dp,dn,fn in os.walk(r):
            if os.path.basename(h) in fn and dp.endswith(os.path.dirname(h)) :
                if 'exclave' not in dp and 'Exclave' not in dp: out.append(os.path.join(dp,os.path.basename(h)))
        if out: return out[0]
    for dp,dn,fn in os.walk(oss):
        if os.path.basename(h) in fn and 'exclave' not in dp.lower() and '/test' not in dp: return os.path.join(dp,os.path.basename(h))
    return None
got=set()
for it in range(60):
    miss=set()
    for f in src:
        r=subprocess.run(['clang++','-std=gnu++20','-arch','arm64','-I.','-Iisa','-I..','-I'+priv,'-fsyntax-only','-D__BRIDGEOS_DEPRECATED(...)=','-D__BRIDGEOS_AVAILABLE(...)=','-D__BRIDGEOS_UNAVAILABLE=','-DNDEBUG','-ferror-limit=1',f],cwd=objc,capture_output=True,text=True)
        m=re.search(r"fatal error: '([^']+)' file not found",r.stderr)
        if m: miss.add(m.group(1))
        elif r.returncode: print(f,'ERR',r.stderr[:600])
    if not miss: print('ok'); break
    for h in miss:
        p=find(h)
        if not p:
            d=os.path.join(priv,os.path.dirname(h)); os.makedirs(d,exist_ok=True)
            open(os.path.join(priv,h),'w').write('#pragma once\n/* stub: not available in the open-source drops */\n'); print('STUB',h); continue
        d=os.path.join(priv,os.path.dirname(h)); os.makedirs(d,exist_ok=True)
        t=open(p,errors='replace').read()
        t=re.sub(r',\s*bridgeos\([^)]*\)','',t); t=re.sub(r'bridgeos\([^)]*\)\s*,?','',t)
        open(os.path.join(priv,h),'w').write(t); print('copied',h,'from',p)
