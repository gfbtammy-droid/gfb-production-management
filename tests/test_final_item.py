import os
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__));REPO=os.path.dirname(HERE);O='https://demo.local/p/'
FAKE=open(os.path.join(HERE,'fake-supabase.js')).read()
def h(route):
    u=route.request.url
    if 'supabase-js' in u: return route.fulfill(status=200,content_type='application/javascript',body=FAKE)
    if u.startswith(O): return route.fulfill(status=200,content_type='text/html',body=open(os.path.join(REPO,'index.html'),'rb').read())
    return route.abort()
res=[];ok=lambda n,c,i='':res.append(('PASS' if c else 'FAIL',n,i))
with sync_playwright() as p:
    br=p.chromium.launch()
    for w,tag in [(1440,'desk'),(390,'mob')]:
        ctx=br.new_context(viewport={'width':w,'height':900},locale='en-GB',timezone_id='Asia/Kuala_Lumpur');ctx.route('**/*',h);pg=ctx.new_page();errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.add_init_script("localStorage.setItem('gfbp_lang','en')")
        pg.goto(O);pg.wait_for_timeout(1500)
        pg.evaluate("Object.assign(S.jobs.find(j=>j.id===1),{item_code:'WIP0021',pack_item_code:'FG0102',customer:'DEMO CAFE'});Object.assign(S.jobs.find(j=>j.id===7),{item_code:'WIP0300'});S.f='ALL';render()");pg.wait_for_timeout(400)
        txt=pg.inner_text('#app')
        ok(tag+' packing job shows FG code','FG0102' in txt)
        ok(tag+' bulk job shows mixing code','WIP0300' in txt)
        if tag=='desk':
            ok('column header','Final Item Code' in txt)
            pg.screenshot(path=os.path.join(HERE,'out','final_item_desk.png'))
            pg.evaluate("openJobForm()");pg.wait_for_timeout(400)
            ok('form has packing item code',pg.locator('#j_pitem').count()==1 and pg.is_visible('#j_pitem'))
            pg.check('#j_bulk');pg.wait_for_timeout(100);ok('hidden for bulk',not pg.is_visible('#j_pitem'))
            pg.uncheck('#j_bulk');pg.fill('#j_product','CHOCOLATE PREMIX 1');pg.fill('#j_customer','DEMO CAFE');pg.dispatch_event('#j_product','change');pg.wait_for_timeout(100)
            ok('auto-fill packing code from last job',pg.input_value('#j_pitem')=='FG0102',pg.input_value('#j_pitem'))
        else:
            pg.screenshot(path=os.path.join(HERE,'out','final_item_mob.png'))
        ok(tag+' no errors',not errs,errs)
        ctx.close()
    br.close()
for r in res:print(*r)
