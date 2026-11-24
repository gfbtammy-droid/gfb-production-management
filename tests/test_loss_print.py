import os
from playwright.sync_api import sync_playwright
HERE=os.path.dirname(os.path.abspath(__file__));REPO=os.path.dirname(HERE);O='https://demo.local/p/'
FAKE=open(os.path.join(HERE,'fake-supabase.js')).read()
def h(route):
    u=route.request.url
    if 'supabase-js' in u: return route.fulfill(status=200,content_type='application/javascript',body=FAKE)
    if u.startswith(O):
        f=os.path.join(REPO,(u[len(O):].split('?')[0] or 'index.html'))
        if os.path.isfile(f):return route.fulfill(status=200,content_type='text/html',body=open(f,'rb').read())
    return route.abort()
res=[];ok=lambda n,c,i='':res.append(('PASS' if c else 'FAIL',n,i))
os.makedirs(os.path.join(HERE,'out'),exist_ok=True)
with sync_playwright() as p:
    br=p.chromium.launch()
    for w,tag in [(1300,'desk'),(390,'mob')]:
        ctx=br.new_context(viewport={'width':w,'height':900},locale='en-GB',timezone_id='Asia/Kuala_Lumpur');ctx.route('**/*',h);pg=ctx.new_page();errs=[];pg.on('pageerror',lambda e:errs.append(str(e)))
        pg.add_init_script("localStorage.setItem('gfbp_lang','en');window.__printed=0;window.print=()=>{window.__printed++}")
        pg.goto(O);pg.wait_for_timeout(1500)
        pg.evaluate("S.tab='loss';S.lossF='ALL';render()");pg.wait_for_timeout(400)
        ok(tag+' list print button',pg.locator('#lprint').count()==1)
        pg.click('#lprint');pg.wait_for_timeout(500)
        ok(tag+' list printed',pg.evaluate("__printed")==1 and 'LOSS-' in pg.inner_text('#printDoc'))
        if tag=='desk':
            pg.emulate_media(media='print');pg.pdf(path=os.path.join(HERE,'out','loss_list.pdf'));pg.emulate_media(media='screen')
        lid=pg.evaluate("S.losses[0].id");pg.evaluate(f"openLoss({lid})");pg.wait_for_timeout(500)
        ok(tag+' report print button',pg.locator('#printL').count()==1)
        pg.click('#printL');pg.wait_for_timeout(500)
        t=pg.inner_text('#printDoc');ok(tag+' report printed',pg.evaluate("__printed")==2 and 'GFB FOOD SDN BHD' in t and 'Verified by' in t,t[:80])
        if tag=='desk':
            pg.emulate_media(media='print');pg.pdf(path=os.path.join(HERE,'out','loss_report.pdf'));pg.emulate_media(media='screen')
        ok(tag+' no errors',not errs,errs)
        ctx.close()
    br.close()
for r in res:print(*r)
