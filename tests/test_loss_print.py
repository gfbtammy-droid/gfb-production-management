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
        if tag=='desk':
            pg.evaluate("openLossForm(null,1)");pg.wait_for_timeout(500)
            pg.select_option('#l_type','WASTAGE');pg.fill('#l_bn','20132');pg.fill('#l_item','WIP0021');pg.fill('#l_mat','Belgium Chocolate (KN-PHs4-FN)')
            pg.fill('#l_qty','11.83');pg.fill('#l_bq','502');pg.fill('#l_cq','490');pg.fill('#l_trans','434621');pg.fill('#l_loc','IBC Area')
            pg.fill('#l_desc','WIP leak from butterfly valve');pg.fill('#l_reason','The lock is loose');pg.fill('#l_act','Replace butterfly valve');pg.click('#ls');pg.wait_for_timeout(800)
            r=pg.evaluate("__T.loss_reports.slice(-1)[0]")
            ok('new fields saved',r.get('trans_no')=='434621' and r.get('batch_qty')==502 and r.get('completed_qty')==490 and r.get('reason')=='The lock is loose' and r.get('item_code')=='WIP0021' and r.get('batch_no')=='20132',r)
            pg.evaluate("closeSheet&&closeSheet()")
        pg.evaluate("S.tab='loss';S.lossF='ALL';render()");pg.wait_for_timeout(400)
        ok(tag+' list print button',pg.locator('#lprint').count()==1)
        pg.click('#lprint');pg.wait_for_timeout(500)
        ok(tag+' list printed one F60 page per report',pg.evaluate("__printed")==1 and pg.evaluate("document.querySelectorAll('#printDoc .f60').length")==pg.evaluate("S.losses.length"))
        if tag=='desk':
            pg.emulate_media(media='print');pg.pdf(path=os.path.join(HERE,'out','loss_list.pdf'));pg.emulate_media(media='screen')
        lid=pg.evaluate("S.losses.find(l=>l.trans_no)?.id||S.losses[0].id");pg.evaluate(f"openLoss({lid})");pg.wait_for_timeout(500)
        ok(tag+' report print button',pg.locator('#printL').count()==1)
        pg.click('#printL');pg.wait_for_timeout(500)
        t=pg.inner_text('#printDoc');ok(tag+' report printed',pg.evaluate("__printed")==2 and 'WASTAGE REPORT (MISC ISSUE)' in t and 'VERIFIED BY' in t and 'Form No.: F60' in t,t[:80])
        if tag=='desk':
            pg.emulate_media(media='print');pg.pdf(path=os.path.join(HERE,'out','loss_report.pdf'));pg.emulate_media(media='screen')
        ok(tag+' no errors',not errs,errs)
        ctx.close()
    br.close()
for r in res:print(*r)
